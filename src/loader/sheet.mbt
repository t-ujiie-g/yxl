// One sheet of the spec: creating it, dispatching its keys to the feature
// loaders, and its presentation — tab visibility, frozen or split panes.
// Document-level structure lives in `loader.mbt`.

///|
fn load_sheets(
  node : @yaml.Node,
  workbook : @model.Workbook,
  file~ : String,
  defs~ : Defs,
  resolve~ : IncludeResolver,
  read_bytes~ : BytesResolver,
) -> Unit raise {
  let items = expect_seq(node, file~, context="'sheets'")
  let seen_names = []
  for item in items {
    let name = load_sheet(item, workbook, file~, defs~, resolve~, read_bytes~)
    guard !seen_names.contains(name) else {
      raise schema_error(file~, "duplicate sheet name '\{name}'")
    }
    seen_names.push(name)
  }
}

///|
/// Add one sheet to the workbook and return its name (for duplicate checking).
fn load_sheet(
  node : @yaml.Node,
  workbook : @model.Workbook,
  file~ : String,
  defs~ : Defs,
  resolve~ : IncludeResolver,
  read_bytes~ : BytesResolver,
) -> String raise {
  let entries = expect_map(node, file~, context="a sheet")
  // `name` and `visibility` are read up front because the sheet cannot be
  // created without them; every other key then applies to the sheet in place.
  guard find_key(entries, "name") is Some(name_node) else {
    raise schema_error(file~, "a sheet is missing required key 'name'")
  }
  let sheet_name = expect_string(name_node, file~, context="sheet 'name'")
  let visibility = match find_key(entries, "visibility") {
    Some(value) => load_visibility(value, file~)
    None => @model.Visible
  }
  guard !(find_key(entries, "freeze") is Some(_) &&
    find_key(entries, "split") is Some(_)) else {
    raise schema_error(
      file~,
      "sheet '\{sheet_name}' cannot combine 'freeze' and 'split'",
    )
  }
  let sheet = workbook.add_sheet(sheet_name, visibility~)
  for entry in entries {
    let (key, value) = entry
    match key {
      "name" | "visibility" => () // consumed above
      "cells" => load_cells(value, sheet, file~, defs~)
      "formulas" => load_formulas(value, sheet, file~)
      "data" => load_data(value, sheet, file~, resolve~)
      "columns" => load_columns(value, sheet, file~, defs~)
      "rows" => load_rows(value, sheet, file~, defs~)
      "merges" => load_merges(value, sheet, file~)
      "freeze" => sheet.set_panes(load_freeze(value, file~))
      "split" => sheet.set_panes(load_split(value, file~))
      "gridlines" =>
        sheet.set_gridlines(
          expect_bool(value, file~, context="sheet 'gridlines'"),
        )
      "tab_color" =>
        sheet.set_tab_color(
          expect_color(value, file~, what="'tab_color'", context="sheet"),
        )
      "print" => sheet.set_page_setup(load_page_setup(value, file~))
      "filter" => load_filter(value, sheet, file~)
      "validations" => load_validations(value, sheet, file~)
      "links" => load_links(value, sheet, file~)
      "conditional" => load_conditional_formats(value, sheet, file~, defs~)
      "comments" => load_comments(value, sheet, file~)
      "tables" => load_tables(value, sheet, file~)
      "charts" => load_charts(value, sheet, file~)
      "images" => load_images(value, sheet, file~, read_bytes~)
      "shapes" => load_shapes(value, sheet, file~)
      "background" => load_background(value, sheet, file~, read_bytes~)
      "sparklines" => load_sparklines(value, sheet, file~)
      "controls" => load_controls(value, sheet, file~)
      "slicers" => load_slicers(value, sheet, file~)
      "pivots" => load_pivots(value, sheet, file~)
      "protect" => sheet.set_protection(load_sheet_protection(value, file~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet (expected 'name', 'cells', 'formulas', 'data', 'columns', 'rows', 'merges', 'visibility', 'freeze', 'split', 'gridlines', 'tab_color', 'print', 'filter', 'validations', 'links', 'conditional', 'comments', 'tables', 'charts', 'images', 'shapes', 'background', 'sparklines', 'controls', 'slicers', 'pivots', or 'protect')",
        )
    }
  }
  sheet_name
}

///|
/// A sheet's `visibility:` — `visible` (the default), `hidden`, or `very_hidden`
/// (unhideable from Excel's UI). A bareword, not a boolean, because Excel has
/// three states, unlike a column or row band's two-state `hidden:`.
fn load_visibility(
  node : @yaml.Node,
  file~ : String,
) -> @model.SheetVisibility raise @diag.SchemaError {
  match expect_string(node, file~, context="sheet 'visibility'") {
    "visible" => Visible
    "hidden" => Hidden
    "very_hidden" => VeryHidden
    other =>
      raise schema_error(
        file~,
        "unknown sheet visibility '\{other}' (expected 'visible', 'hidden', or 'very_hidden')",
      )
  }
}

///|
/// A sheet's `freeze: <cell>` — the rows above and columns left of that cell
/// stay put while the rest scrolls. `A1` freezes nothing, so it is a mistake
/// worth reporting rather than a no-op.
fn load_freeze(
  node : @yaml.Node,
  file~ : String,
) -> @model.Panes raise @diag.SchemaError {
  let reference = expect_string(node, file~, context="sheet 'freeze'")
  let cell = expect_cell_ref(reference, file~, what="'freeze'")
  guard cell.col > 1 || cell.row > 1 else {
    raise schema_error(
      file~,
      "'freeze: A1' would freeze nothing (freeze at the first unfrozen cell)",
    )
  }
  Freeze(cell)
}

///|
/// A sheet's `split: { x, y }` — a draggable splitter, each axis given in points
/// from the top-left corner and defaulting to `0` (that axis unsplit). Splitting
/// on neither axis is a mistake worth reporting.
fn load_split(
  node : @yaml.Node,
  file~ : String,
) -> @model.Panes raise @diag.SchemaError {
  let mut x = 0.0
  let mut y = 0.0
  for entry in expect_map(node, file~, context="sheet 'split'") {
    let (key, value) = entry
    match key {
      "x" => x = expect_number(value, file~, context="sheet 'split' x")
      "y" => y = expect_number(value, file~, context="sheet 'split' y")
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet 'split' (expected 'x' or 'y')",
        )
    }
  }
  guard x > 0.0 || y > 0.0 else {
    raise schema_error(
      file~,
      "sheet 'split' needs a non-zero 'x' or 'y' (in points)",
    )
  }
  Split(x~, y~)
}
