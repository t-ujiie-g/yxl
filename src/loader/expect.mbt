// The shared vocabulary every loader file speaks: turning a `yaml.Node` into the
// scalar or collection the schema expects, and turning a mismatch into a
// `@diag.SchemaError` naming the file and what was being read (ADR-006). Each
// takes a `context` describing the owner ("cell 'A1'", "'sheets'"), which is
// what makes the diagnostics readable. Structural loading lives in `loader.mbt`.

///|
/// A diagnostic naming the source file, the pipeline's one way to report a bad
/// spec.
fn schema_error(file~ : String, message : String) -> @diag.SchemaError {
  @diag.SchemaError(@diag.Diagnostic::new("\{file}: \{message}"))
}

///|
/// The value of the first `key` entry in a mapping's entries, or `None`.
fn find_key(entries : Array[(String, @yaml.Node)], key : String) -> @yaml.Node? {
  for entry in entries {
    let (candidate, value) = entry
    if candidate == key {
      return Some(value)
    }
  }
  None
}

///|
fn expect_map(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Array[(String, @yaml.Node)] raise @diag.SchemaError {
  match node {
    @yaml.Map(entries) => entries
    _ => raise schema_error(file~, "\{context} must be a mapping")
  }
}

///|
fn expect_string(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => text
    _ => raise schema_error(file~, "\{context} must be text")
  }
}

///|
fn expect_seq(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Array[@yaml.Node] raise @diag.SchemaError {
  match node {
    @yaml.Seq(items) => items
    _ => raise schema_error(file~, "\{context} must be a sequence")
  }
}

///|
fn expect_bool(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Bool raise @diag.SchemaError {
  match node {
    @yaml.Bool(flag) => flag
    _ => raise schema_error(file~, "\{context} must be true or false")
  }
}

///|
/// A number scalar (integer or float) as a `Double`.
fn expect_number(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Double raise @diag.SchemaError {
  match node {
    @yaml.Int(number) => number.to_double()
    @yaml.Float(number) => number
    _ => raise schema_error(file~, "\{context} must be a number")
  }
}

///|
/// A hex-color scalar, validated into a `@units.Color`. `what` names the
/// attribute for the diagnostic (e.g. `"font 'color'"`).
fn expect_color(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
  context~ : String,
) -> @units.Color raise @diag.SchemaError {
  let text = expect_string(node, file~, context="\{context} \{what}")
  guard @units.Color::parse(text) is Some(color) else {
    raise schema_error(
      file~,
      "\{context} \{what} is not a valid hex color: '\{text}'",
    )
  }
  color
}

///|
/// An A1-style cell reference, validated. `what` names the construct the
/// reference appeared in, so the diagnostic says *which* one is bad; omit it
/// where the reference is the whole subject (a `cells:` key).
fn expect_cell_ref(
  reference : String,
  file~ : String,
  what? : String,
) -> @units.CellRef raise @diag.SchemaError {
  guard @units.CellRef::parse_a1(reference) is Some(cell) else {
    let within = match what {
      Some(what) => " in \{what}"
      None => ""
    }
    raise schema_error(
      file~,
      "'\{reference}' is not a valid A1 cell reference\{within}",
    )
  }
  cell
}
