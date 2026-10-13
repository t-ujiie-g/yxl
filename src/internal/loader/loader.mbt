///|
/// Load a parsed spec into a workbook model, validating it against `docs/spec.md`;
/// a violation is a `@diag.SchemaError` naming `file` (ADR-006). `$include` nodes
/// are read through `resolve` (ADR-014).
pub fn load(
  document : @yaml.Node,
  file~ : String,
  resolve~ : IncludeResolver = no_includes,
  read_bytes~ : BytesResolver = no_binaries,
  params~ : Map[String, String] = Map([]),
) -> @model.Workbook raise {
  // Two pre-passes collapse a multi-file, parameterized spec into the single
  // plain tree every reader below sees (ADR-005, ADR-014). Includes expand
  // first, so an included file may use the parameters too.
  let document = expand_includes(document, file~, resolve~, chain=[file])
  let document = substitute_params(document, file~, overrides=params)
  let root = expect_map(document, file~, context="the top level")
  let workbook = @model.Workbook(
    date_system=read_date_system(root, file~),
    default_font?=read_default_font(root, file~),
  )
  // Registers each declared value/formula as a workbook defined name (ADR-013).
  let defs = load_defs(root, workbook, file~)
  settle_layouts(root, defs~, file~, resolve~)
  let mut seen_sheets = false
  for entry in root {
    let (key, value) = entry
    match key {
      "sheets" => {
        seen_sheets = true
        load_sheets(value, workbook, file~, defs~, resolve~, read_bytes~)
      }
      "date1904" => () // consumed by read_date_system
      "default_font" => () // consumed by read_default_font
      DEFS_KEY => () // consumed by load_defs
      "active" => () // resolved below, once every sheet name is known
      "properties" => workbook.set_properties(load_properties(value, file~))
      "calc" => workbook.set_calc(load_calc(value, file~))
      "protect" =>
        workbook.set_protection(load_workbook_protection(value, file~))
      "output" => workbook.set_output(load_output(value, file~))
      PARAMS_KEY => () // consumed by the substitution pass
      OVERRIDES_KEY => () // loaded below, once every layout has a place
      _ =>
        raise schema_error(
          file~,
          "unknown top-level key '\{key}' (expected 'sheets', 'output', 'active', 'params', 'overrides', 'date1904', 'default_font', 'defs', 'properties', 'calc', or 'protect')",
        )
    }
  }
  guard seen_sheets else {
    raise schema_error(file~, "missing required key 'sheets'")
  }
  add_layout_names(workbook, defs)
  if find_key(root, OVERRIDES_KEY) is Some(overrides) {
    load_overrides(overrides, workbook, file~, defs~)
  }
  read_active_sheet(root, workbook, file~)
  check_cross_sheet_references(workbook, file~)
  check_tables(workbook, file~)
  check_defined_names(workbook, file~)
  check_formula_ranges(workbook, file~)
  check_overrides(workbook, file~)
  check_slicers(workbook, file~)
  check_pivots(workbook, file~)
  // Two different mistakes, and one message for both would name neither: an
  // empty `sheets:` has no sheet to unhide, and a workbook of hidden sheets has
  // sheets but no tab Excel can open on.
  guard !workbook.sheets.is_empty() else {
    raise schema_error(file~, "'sheets' is empty; a workbook needs a sheet")
  }
  guard workbook.sheets.iter().any(sheet => sheet.visibility is Visible) else {
    raise schema_error(
      file~,
      "every sheet is hidden; Excel needs at least one visible sheet",
    )
  }
  workbook
}

///|
/// The optional top-level `active: <sheet name>` selects the sheet Excel opens
/// on; its absence opens the first sheet. The name must be a declared, visible
/// sheet — Excel cannot open on a tab it does not show.
fn read_active_sheet(
  root : Array[(String, @yaml.Node)],
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  guard find_key(root, "active") is Some(value) else { return }
  let name = expect_string(value, file~, context="'active'")
  guard workbook.sheet(name) is Some(sheet) else {
    raise schema_error(file~, "active sheet '\{name}' is not a declared sheet")
  }
  guard sheet.visibility is Visible else {
    raise schema_error(file~, "active sheet '\{name}' is hidden")
  }
  workbook.set_active_sheet(name)
}

///|
/// The optional top-level `date1904: true` selects the 1904 date system; its
/// absence (or `false`) keeps the 1900 default.
fn read_date_system(
  root : Array[(String, @yaml.Node)],
  file~ : String,
) -> @units.DateSystem raise @diag.SchemaError {
  match find_key(root, "date1904") {
    Some(value) =>
      if expect_bool(value, file~, context="'date1904'") {
        Date1904
      } else {
        Date1900
      }
    None => Date1900
  }
}

///|
/// The optional top-level `default_font: <name>` sets the workbook default font
/// face; its absence keeps the backend default.
fn read_default_font(
  root : Array[(String, @yaml.Node)],
  file~ : String,
) -> String? raise @diag.SchemaError {
  guard find_key(root, "default_font") is Some(value) else { return None }
  Some(expect_string(value, file~, context="'default_font'"))
}

///|
/// The top-level `output:` path. Anything but a `.xlsx` name would write a file
/// Excel refuses to open, so it is caught here rather than on open.
fn load_output(
  value : @yaml.Node,
  file~ : String,
) -> String raise @diag.SchemaError {
  let path = expect_string(value, file~, context="'output'")
  guard path.to_lower().has_suffix(".xlsx") else {
    raise schema_error(
      file~,
      "'output' must name a .xlsx file, but is '\{path}'",
    )
  }
  path
}

///|
/// Load a sheet's `merges:` sequence: each entry is a range string
/// `TopLeft:BottomRight` (e.g. `A1:B2`) merged into one cell. Corners may be
/// given in any order; the model canonicalizes them.
fn load_merges(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'merges'") {
    let text = expect_string(item, file~, context="a merge range")
    let range = parse_range(text, file~, what="merge range")
    sheet.merge(range.top_left, range.bottom_right)
  }
}

///|
fn load_cells(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="'cells'")
  for entry in entries {
    let (reference, value_node) = entry
    let cell = expect_cell_ref(reference, file~)
    let (value, style) = load_cell(value_node, file~, reference~, defs~)
    sheet.set(cell, value, style?)
  }
}
