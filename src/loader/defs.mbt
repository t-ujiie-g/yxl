// Named definitions and reference resolution for the loader (ADR-012). The
// top-level `defs:` block declares reusable `styles`, `values`, and `formulas`
// once; cells, columns, and rows reference them by name (a bareword for styles,
// `{ $ref: name }` for values and formulas). References resolve here to the same
// model value/style, so the emitter's structural interning (ADR-004) collapses
// them to one shared string / `cellXfs` id. A reference to a name that was never
// defined is a fail-fast `@diag.SchemaError` (ADR-006).

///|
/// The named definitions in scope while loading a workbook, one namespace per
/// kind: a reference's kind is fixed by where it appears (`style:` a style,
/// `value:` a value, `formula:` a formula), so the same name may exist in more
/// than one namespace without ambiguity.
priv struct Defs {
  styles : Map[String, @model.Style]
  values : Map[String, @model.CellValue]
  formulas : Map[String, String]
}

///|
/// The empty definition set — no names in any namespace.
fn Defs::empty() -> Defs {
  { styles: Map([]), values: Map([]), formulas: Map([]) }
}

///|
/// Read the optional top-level `defs:` block into a `Defs`. Its keys are
/// `styles`, `values`, and `formulas`, each a mapping of name to definition; an
/// absent `defs` yields the empty set. A style definition takes the same shape
/// as a cell `style:` mapping; a value is a scalar; a formula is a string (a
/// leading `=` is stripped on use, as for cell formulas).
fn load_defs(
  root : Array[(String, @yaml.Node)],
  file~ : String,
) -> Defs raise @diag.SchemaError {
  let defs = Defs::empty()
  guard find_key(root, "defs") is Some(node) else { return defs }
  for entry in expect_map(node, file~, context="'defs'") {
    let (key, value) = entry
    match key {
      "styles" => load_style_defs(value, defs, file~)
      "values" => load_value_defs(value, defs, file~)
      "formulas" => load_formula_defs(value, defs, file~)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in 'defs' (expected 'styles', 'values', or 'formulas')",
        )
    }
  }
  defs
}

///|
fn load_style_defs(
  node : @yaml.Node,
  defs : Defs,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_map(node, file~, context="'defs.styles'") {
    let (name, style_node) = entry
    defs.styles[name] = load_style(style_node, file~, context="style '\{name}'")
  }
}

///|
fn load_value_defs(
  node : @yaml.Node,
  defs : Defs,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_map(node, file~, context="'defs.values'") {
    let (name, value_node) = entry
    defs.values[name] = scalar_value(
      value_node,
      file~,
      context="value definition '\{name}'",
    )
  }
}

///|
fn load_formula_defs(
  node : @yaml.Node,
  defs : Defs,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_map(node, file~, context="'defs.formulas'") {
    let (name, formula_node) = entry
    defs.formulas[name] = expect_string(
      formula_node,
      file~,
      context="formula definition '\{name}'",
    )
  }
}

///|
/// A `{ $ref: name }` node yields the referenced name; any other node is `None`.
/// The mapping must have exactly the single `$ref` key with a string value.
fn as_ref(node : @yaml.Node) -> String? {
  guard node is @yaml.Map([("$ref", @yaml.Str(name))]) else { return None }
  Some(name)
}

///|
/// Look a value reference up in `defs.values`; an undefined name is a
/// fail-fast diagnostic naming the referencing cell.
fn resolve_value_ref(
  name : String,
  file~ : String,
  reference~ : String,
  defs~ : Defs,
) -> @model.CellValue raise @diag.SchemaError {
  match defs.values.get(name) {
    Some(value) => value
    None =>
      raise schema_error(
        file~,
        "cell '\{reference}' references undefined value '\{name}'",
      )
  }
}

///|
/// Resolve a cell's `formula:` node: a `{ $ref: name }` looks the formula up in
/// `defs.formulas`, otherwise the node is an inline formula string. The result
/// is the raw formula; the caller strips a leading `=`.
fn resolve_formula(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
  defs~ : Defs,
) -> String raise @diag.SchemaError {
  match as_ref(node) {
    Some(name) =>
      match defs.formulas.get(name) {
        Some(formula) => formula
        None =>
          raise schema_error(
            file~,
            "cell '\{reference}' references undefined formula '\{name}'",
          )
      }
    None => expect_string(node, file~, context="cell '\{reference}' formula")
  }
}
