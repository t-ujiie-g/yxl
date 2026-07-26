// Parameterization: a top-level `params:` block declares named values with
// defaults, `${name}` in any string substitutes one, and the CLI's `--set` can
// override a default without editing the spec — one spec, many workbooks.
//
// Like includes, this is a pre-pass over the document tree that runs before any
// schema key is interpreted, so every reader below sees a spec with no
// parameters left in it. It runs *after* include expansion, so an included file
// may use the parameters too.

///|
/// The mapping key that declares parameters.
const PARAMS_KEY : String = "params"

///|
/// Substitute `${name}` throughout a document from its own `params:` block, with
/// `overrides` (from `--set`) replacing the declared defaults. A document with
/// no `params:` and no overrides is returned untouched.
///
/// An override naming no declared parameter is a diagnostic: a typo on the
/// command line should say so, not quietly do nothing.
fn substitute_params(
  document : @yaml.Node,
  file~ : String,
  overrides~ : Map[String, String],
) -> @yaml.Node raise @diag.SchemaError {
  let declared = match document {
    @yaml.Map(entries) =>
      match find_key(entries, PARAMS_KEY) {
        Some(node) => expect_map(node, file~, context="'\{PARAMS_KEY}'")
        None => []
      }
    _ => []
  }
  for name in overrides.keys() {
    guard find_key(declared, name) is Some(_) else {
      raise schema_error(
        file~,
        "cannot set '\{name}': the spec declares no such parameter",
      )
    }
  }
  // The pass runs even when nothing is declared: a `${name}` no parameter backs
  // must be a diagnostic, not a literal that survives into a cell (ADR-006).
  let params = resolve_params(declared, overrides, file~)
  substitute(document, params, file~)
}

///|
/// Resolve every declared parameter to a scalar. A default may itself contain
/// `${other}`, so resolution is depth-first with the chain of names being
/// resolved carried along to detect a cycle. An override replaces the default
/// outright, and is read as the scalar it looks like — the value arrives from a
/// command line as text, and `--set rate=0.08` should be the number.
fn resolve_params(
  declared : Array[(String, @yaml.Node)],
  overrides : Map[String, String],
  file~ : String,
) -> Map[String, @yaml.Node] raise @diag.SchemaError {
  let resolved : Map[String, @yaml.Node] = Map([])
  for entry in declared {
    let (name, _) = entry
    resolve_param(name, declared, overrides, resolved, file~, chain=[])
    |> ignore
  }
  resolved
}

///|
/// Resolve one parameter, first resolving any parameter its default names.
fn resolve_param(
  name : String,
  declared : Array[(String, @yaml.Node)],
  overrides : Map[String, String],
  resolved : Map[String, @yaml.Node],
  file~ : String,
  chain~ : Array[String],
) -> @yaml.Node raise @diag.SchemaError {
  if resolved.get(name) is Some(value) {
    return value
  }
  guard !chain.contains(name) else {
    raise schema_error(file~, "parameter cycle: \{render_cycle(chain, name)}")
  }
  guard find_key(declared, name) is Some(default) else {
    let from = chain[chain.length() - 1]
    raise schema_error(
      file~,
      "parameter '\{from}' uses undeclared parameter '\{name}'",
    )
  }
  let value = match overrides.get(name) {
    Some(text) => infer_scalar(text)
    None =>
      match default {
        @yaml.Str(text) =>
          interpolate(text, file~, context="parameter '\{name}'", lookup=other => {
            resolve_param(
              other,
              declared,
              overrides,
              resolved,
              file~,
              chain=[..chain, name],
            )
          })
        scalar => expect_scalar(scalar, file~, context="parameter '\{name}'")
      }
  }
  resolved[name] = value
  value
}

///|
/// Replace `${name}` throughout a tree. Mapping keys are substituted too — so a
/// cell reference or a sheet name may be parameterized — and always render as
/// text, since a key is one.
fn substitute(
  node : @yaml.Node,
  params : Map[String, @yaml.Node],
  file~ : String,
) -> @yaml.Node raise @diag.SchemaError {
  match node {
    @yaml.Str(text) =>
      interpolate(text, file~, context="a value", lookup=name => {
        lookup_param(name, params, file~)
      })
    @yaml.Map(entries) => {
      let substituted = []
      for entry in entries {
        let (key, value) = entry
        let key = scalar_text(
          interpolate(key, file~, context="key '\{key}'", lookup=name => {
            lookup_param(name, params, file~)
          }),
        )
        substituted.push((key, substitute(value, params, file~)))
      }
      @yaml.Map(substituted)
    }
    @yaml.Seq(items) => {
      let substituted = []
      for item in items {
        substituted.push(substitute(item, params, file~))
      }
      @yaml.Seq(substituted)
    }
    scalar => scalar
  }
}

///|
/// A declared parameter's value, or a diagnostic naming the missing one.
fn lookup_param(
  name : String,
  params : Map[String, @yaml.Node],
  file~ : String,
) -> @yaml.Node raise @diag.SchemaError {
  guard params.get(name) is Some(value) else {
    raise schema_error(file~, "undeclared parameter '\{name}'")
  }
  value
}

///|
/// Expand `${name}` in one string. A string that is *exactly* one placeholder
/// takes the parameter's own type, so `"${rate}"` can be a number cell; anything
/// else composes text. `$$` is a literal `$`, and a `$` that begins neither
/// escape is itself — which leaves Excel's absolute references (`$A$1`) alone.
///
/// The one place the two `$` meanings collide is a literal `$` *immediately*
/// before a placeholder: `$B$${n}` reads its middle `$$` as the escape and
/// leaves `{n}` alone. Write `$B$$${n}` — an escaped `$` then the placeholder.
fn interpolate(
  text : String,
  file~ : String,
  context~ : String,
  lookup~ : (String) -> @yaml.Node raise @diag.SchemaError,
) -> @yaml.Node raise @diag.SchemaError {
  let chars = text.iter().to_array()
  let built = StringBuilder::new()
  // The value of a lone placeholder, kept typed until something else appears.
  let mut only = None
  let mut index = 0
  while index < chars.length() {
    let ch = chars[index]
    if ch != '$' {
      built.write_char(ch)
      only = None
      index += 1
      continue
    }
    if index + 1 < chars.length() && chars[index + 1] == '$' {
      built.write_char('$')
      only = None
      index += 2
      continue
    }
    if index + 1 < chars.length() && chars[index + 1] == '{' {
      let close = find_close(chars, index + 2)
      guard close is Some(close) else {
        raise schema_error(file~, "\{context} has a '${' with no closing '}'")
      }
      let name = collect_chars(chars, index + 2, close)
      let value = lookup(name)
      // A lone placeholder keeps its type; once anything else joins it, the
      // result is composed text.
      only = if built.to_string() == "" && close + 1 == chars.length() {
        Some(value)
      } else {
        None
      }
      built.write_string(scalar_text(value))
      index = close + 1
      continue
    }
    built.write_char(ch)
    only = None
    index += 1
  }
  match only {
    Some(value) => value
    None => @yaml.Str(built.to_string())
  }
}

///|
/// The index of the `}` closing a placeholder opened before `start`.
fn find_close(chars : Array[Char], start : Int) -> Int? {
  for index in start..<chars.length() {
    if chars[index] == '}' {
      return Some(index)
    }
  }
  None
}

///|
/// The characters in `[start, end)` as a string.
fn collect_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let built = StringBuilder::new()
  for index in start..<end {
    built.write_char(chars[index])
  }
  built.to_string()
}

///|
/// A scalar node rendered as the text it contributes to a composed string.
fn scalar_text(node : @yaml.Node) -> String {
  match node {
    @yaml.Str(text) => text
    @yaml.Int(number) => number.to_string()
    @yaml.Float(number) => number.to_string()
    @yaml.Bool(flag) => if flag { "true" } else { "false" }
    @yaml.Null => ""
    _ => ""
  }
}

///|
/// A scalar node, or a diagnostic: a parameter holds one value, not a structure.
fn expect_scalar(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @yaml.Node raise @diag.SchemaError {
  match node {
    @yaml.Str(_) | @yaml.Int(_) | @yaml.Float(_) | @yaml.Bool(_) => node
    _ =>
      raise schema_error(
        file~,
        "\{context} must be text, a number, or a boolean",
      )
  }
}

///|
/// Untyped text as the scalar it looks like. Shared by `--set` values, which
/// arrive from a command line, and CSV fields, which carry no types either.
fn infer_scalar(text : String) -> @yaml.Node {
  match text {
    "true" => @yaml.Bool(true)
    "false" => @yaml.Bool(false)
    _ => @yaml.Float(@string.parse_double(text)) catch { _ => @yaml.Str(text) }
  }
}
