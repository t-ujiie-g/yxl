// Named definitions and reference resolution for the loader (ADR-012, ADR-013).
// The top-level `defs:` block declares reusable `styles`, `values`, and
// `formulas` once; cells, columns, and rows reference them by name (a bareword
// for styles, `{ $ref: name }` for values and formulas).
//
// Each declared value/formula is registered as a workbook *defined name*, and a
// value/formula reference compiles to the formula `=name` — so editing the
// defined name in Excel updates every reference (ADR-013). A style reference
// instead resolves to the same model style, which the emitter's structural
// interning (ADR-004) collapses to one `cellXfs` id. A reference to a name that
// was never defined is a fail-fast `@diag.SchemaError` (ADR-006).

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
  workbook : @model.Workbook,
  file~ : String,
) -> Defs raise @diag.SchemaError {
  let defs = Defs::empty()
  guard find_key(root, "defs") is Some(node) else { return defs }
  for entry in expect_map(node, file~, context="'defs'") {
    let (key, value) = entry
    match key {
      "styles" => load_style_defs(value, defs, file~)
      "values" => load_value_defs(value, defs, workbook, file~)
      "formulas" => load_formula_defs(value, defs, workbook, file~)
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
/// Read `defs.styles`. A definition may `extends:` another declared style —
/// including one declared *later*, so the block reads in whatever order suits
/// the author — which is resolved depth-first and memoized as each name lands in
/// `defs.styles`. Declaration order is kept for the walk so a spec with an error
/// reports the same one every time.
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
/// Resolve one style definition, following `extends:` first. `chain` is the
/// names being resolved, outermost first: it both detects a cycle and renders
/// it. A resolved style is memoized in `defs.styles`, so a shared base is
/// parsed once however many styles extend it.
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
    raise schema_error(
      file~,
      "style inheritance cycle: \{render_cycle(chain, name)}",
    )
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
/// A `{ $ref: name }` node yields the referenced name; any other node is `None`.
/// The mapping must have exactly the single `$ref` key with a string value.
fn as_ref(node : @yaml.Node) -> String? {
  guard node is @yaml.Map([("$ref", @yaml.Str(name))]) else { return None }
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
/// Resolve a cell's `formula:` node to the formula body the cell emits. A
/// `{ $ref: name }` compiles to `=name` (the referencing name is the body, and
/// the workbook defined name carries the actual formula — ADR-013); a string is
/// an inline formula. Either way the caller strips a leading `=`.
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
