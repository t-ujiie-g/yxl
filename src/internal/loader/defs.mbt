///|
/// The named definitions in scope, one namespace per kind. Where a reference
/// appears fixes its kind, so one name may live in several namespaces.
priv struct Defs {
  styles : Map[String, @model.Style]
  values : Map[String, @model.CellValue]
  formulas : Map[String, String]
  blocks : Map[String, Array[@yaml.Node]]
  layouts : Map[String, NamedLayout]
}

///|
/// The empty definition set — no names in any namespace.
fn Defs::empty() -> Defs {
  {
    styles: Map([]),
    values: Map([]),
    formulas: Map([]),
    blocks: Map([]),
    layouts: Map([]),
  }
}

///|
/// Read the optional `defs:` block (`docs/spec.md` §5); absent, it is empty.
fn load_defs(
  root : Array[(String, @yaml.Node)],
  workbook : @model.Workbook,
  file~ : String,
) -> Defs raise @diag.SchemaError {
  let defs = Defs::empty()
  guard find_key(root, DEFS_KEY) is Some(node) else { return defs }
  for entry in expect_map(node, file~, context="'\{DEFS_KEY}'") {
    let (key, value) = entry
    match key {
      "styles" => load_style_defs(value, defs, file~)
      "values" => load_value_defs(value, defs, workbook, file~)
      "formulas" => load_formula_defs(value, defs, workbook, file~)
      "blocks" => load_block_defs(value, defs, file~)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in 'defs' (expected 'styles', 'values', 'formulas', or 'blocks')",
        )
    }
  }
  defs
}

///|
/// Read `defs.styles`, resolving `extends:` depth-first so a style may extend
/// one declared later; declaration order keeps errors deterministic.
fn load_style_defs(
  node : @yaml.Node,
  defs : Defs,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  let declared = expect_map(node, file~, context="'defs.styles'")
  for entry in declared {
    let (name, _) = entry
    resolve_style_def(name, declared, defs, file~, chain=[]) |> ignore
  }
}

///|
/// Resolve one style definition, `extends:` first. `chain`, outermost first,
/// detects and renders a cycle; a resolved style is memoized in `defs.styles`.
fn resolve_style_def(
  name : String,
  declared : Array[(String, @yaml.Node)],
  defs : Defs,
  file~ : String,
  chain~ : Array[String],
) -> @model.Style raise @diag.SchemaError {
  if defs.styles.get(name) is Some(resolved) {
    return resolved
  }
  guard !chain.contains(name) else {
    raise cycle_error(chain, name, kind="style inheritance", file~)
  }
  guard find_key(declared, name) is Some(node) else {
    // Only reachable through an `extends:`; the walk itself starts on declared
    // names, so `chain` names whoever asked for this one.
    let from = chain[chain.length() - 1]
    raise schema_error(
      file~,
      "style '\{from}' extends undefined style '\{name}'",
    )
  }
  let style = load_style(node, file~, context="style '\{name}'", find_base=base => {
    resolve_style_def(base, declared, defs, file~, chain=[..chain, name])
  })
  defs.styles[name] = style
  style
}

///|
fn load_value_defs(
  node : @yaml.Node,
  defs : Defs,
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_map(node, file~, context="'defs.values'") {
    let (name, value_node) = entry
    let value = scalar_value(
      value_node,
      file~,
      context="value definition '\{name}'",
    )
    defs.values[name] = value
    workbook.add_defined_name(name, value)
  }
}

///|
fn load_formula_defs(
  node : @yaml.Node,
  defs : Defs,
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_map(node, file~, context="'defs.formulas'") {
    let (name, formula_node) = entry
    let formula = strip_leading_equals(
      expect_string(formula_node, file~, context="formula definition '\{name}'"),
    )
    defs.formulas[name] = formula
    workbook.add_defined_name(name, @model.Formula(formula~, cached=None))
  }
}

///|
/// The mapping key that marks a reference to a named definition (ADR-012), the
/// `$`-marked directive `$include` and `params` substitution follow.
const REF_KEY : String = "$ref"

///|
/// The top-level mapping key that declares named definitions.
const DEFS_KEY : String = "defs"

///|
/// A `{ $ref: name }` node yields the referenced name; any other node is
/// `None`. The mapping must have exactly the single `$ref` key with a string
/// value.
fn as_ref(node : @yaml.Node) -> String? {
  guard node is @yaml.Map([(key, @yaml.Str(name))]) && key == REF_KEY else {
    return None
  }
  Some(name)
}

///|
/// Resolve a value reference to the formula `=name` referencing the workbook
/// defined name (ADR-013), caching the definition's constant so the cell shows
/// it until Excel recomputes. An undefined name is a fail-fast diagnostic.
fn resolve_value_ref(
  name : String,
  file~ : String,
  reference~ : String,
  defs~ : Defs,
) -> @model.CellValue raise @diag.SchemaError {
  match defs.values.get(name) {
    Some(value) => @model.Formula(formula=name, cached=Some(value))
    None =>
      raise schema_error(
        file~,
        "cell '\{reference}' references undefined value '\{name}'",
      )
  }
}

///|
/// A cell's `formula:` as the body it emits: `{ $ref: name }` is `=name`, the
/// defined name holding the formula (ADR-013); a string is inline.
fn resolve_formula(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
  defs~ : Defs,
) -> String raise @diag.SchemaError {
  match as_ref(node) {
    Some(name) =>
      if defs.formulas.get(name) is Some(_) {
        name
      } else {
        raise schema_error(
          file~,
          "cell '\{reference}' references undefined formula '\{name}'",
        )
      }
    None => expect_string(node, file~, context="cell '\{reference}' formula")
  }
}
