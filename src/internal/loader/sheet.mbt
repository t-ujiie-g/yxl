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
/// Excel's sheet-name rules (ECMA-376 §18.4.7 and its UI), checked here so the
/// diagnostic names the sheet and rule, not `InvalidSheetName` (ADR-006).
fn check_sheet_name(
  name : String,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  fn refuse(reason : String) -> @diag.SchemaError {
    schema_error(file~, "sheet name '\{name}' \{reason}")
  }

  guard !name.is_empty() else {
    raise schema_error(file~, "a sheet's 'name' is empty; Excel needs a name")
  }
  guard name.char_length() <= max_sheet_name_length else {
    raise refuse(
      "is \{name.char_length()} characters; Excel allows at most \{max_sheet_name_length}",
    )
  }
  for ch in name {
    if forbidden_sheet_name_chars.contains(ch) {
      raise refuse(
        "contains '\{ch}', which Excel does not allow in a sheet name",
      )
    }
  }
  // Excel writes its own `History` sheet when a workbook is shared, so the name
  // is reserved whatever its case.
  guard name.to_lower() != reserved_sheet_name.to_lower() else {
    raise refuse("is reserved by Excel for a shared workbook's change log")
  }
  guard !(name.has_prefix("'") || name.has_suffix("'")) else {
    raise refuse(
      "starts or ends with an apostrophe, which Excel uses to quote a sheet name in a reference",
    )
  }
}

///|
/// The longest sheet name Excel accepts.
let max_sheet_name_length : Int32 = 31

///|
/// The characters Excel refuses in a sheet name — the four a formula reference
/// would misread, plus the two that delimit a workbook name.
let forbidden_sheet_name_chars : Array[Char] = [
  ':', '\\', '/', '?', '*', '[', ']',
]

///|
/// The one name Excel keeps for itself.
let reserved_sheet_name : String = "History"

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
  check_sheet_name(sheet_name, file~)
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
      "formulas" => load_formulas(value, sheet, file~, defs~)
      "data" => load_data(value, sheet, file~, defs~, resolve~)
      "columns" => load_columns(value, sheet, file~, defs~)
      "layouts" => load_layouts(value, sheet, file~, defs~, resolve~)
      "rows" => load_rows(value, sheet, file~, defs~)
      "merges" => load_merges(value, sheet, file~)
      "freeze" =>
        sheet.set_panes(load_freeze(value, file~, defs~, sheet=sheet_name))
      "split" => sheet.set_panes(load_split(value, file~))
      "gridlines" =>
        sheet.set_gridlines(
          expect_bool(value, file~, context="sheet 'gridlines'"),
        )
      "tab_color" =>
        sheet.set_tab_color(
          expect_color(value, file~, what="'tab_color'", context="sheet"),
        )
      "print" =>
        sheet.set_page_setup(
          load_page_setup(value, file~, defs~, sheet=sheet_name),
        )
      "filter" => load_filter(value, sheet, file~, defs~)
      "validations" => load_validations(value, sheet, file~, defs~)
      "links" => load_links(value, sheet, file~, defs~)
      "conditional" => load_conditional_formats(value, sheet, file~, defs~)
      "comments" => load_comments(value, sheet, file~, defs~)
      "tables" => load_tables(value, sheet, file~, defs~)
      "charts" => load_charts(value, sheet, file~, defs~)
      "images" => load_images(value, sheet, file~, defs~, read_bytes~)
      "shapes" => load_shapes(value, sheet, file~, defs~)
      "background" => load_background(value, sheet, file~, read_bytes~)
      "sparklines" => load_sparklines(value, sheet, file~, defs~)
      "controls" => load_controls(value, sheet, file~, defs~)
      "slicers" => load_slicers(value, sheet, file~, defs~)
      "pivots" => load_pivots(value, sheet, file~, defs~)
      "protect" => sheet.set_protection(load_sheet_protection(value, file~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet (expected 'name', 'cells', 'formulas', 'data', 'columns', 'layouts', 'rows', 'merges', 'visibility', 'freeze', 'split', 'gridlines', 'tab_color', 'print', 'filter', 'validations', 'links', 'conditional', 'comments', 'tables', 'charts', 'images', 'shapes', 'background', 'sparklines', 'controls', 'slicers', 'pivots', or 'protect')",
        )
    }
  }
  sheet_name
}

///|
/// A sheet's `visibility:`, a bareword because Excel has three states:
/// `visible`, `hidden`, and `very_hidden`, which Excel's UI cannot undo.
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
/// A sheet's `freeze:` at a cell, or `{ layout, columns }` above a layout's
/// body and through its first `columns`. Freezing nothing is refused.
fn load_freeze(
  node : @yaml.Node,
  file~ : String,
  defs~ : Defs,
  sheet~ : String,
) -> @model.Panes raise @diag.SchemaError {
  if node is @yaml.Map(entries) {
    return Freeze(freeze_at_layout(entries, file~, defs~, sheet~))
  }
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
fn freeze_at_layout(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  defs~ : Defs,
  sheet~ : String,
) -> @units.CellRef raise @diag.SchemaError {
  let mut name = None
  let mut columns = 0
  for entry in entries {
    match entry {
      ("layout", node) =>
        name = Some(expect_string(node, file~, context="freeze 'layout'"))
      ("columns", @yaml.Int(count)) if count >= 0L => columns = count.to_int()
      ("columns", _) =>
        raise schema_error(
          file~,
          "freeze 'columns' must be a whole number of columns, 0 or more",
        )
      (key, _) =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet 'freeze' (expected 'layout' or 'columns')",
        )
    }
  }
  guard name is Some(name) else {
    raise schema_error(
      file~,
      "sheet 'freeze' must be a cell, or '{ layout: name }' to freeze above its body",
    )
  }
  let layout = required_layout_here(
    name,
    defs~,
    sheet~,
    file~,
    what="freeze layout",
  )
  guard columns <= layout.columns.length() else {
    raise schema_error(
      file~,
      "freeze 'columns' is \{columns}, but layout '\{name}' has \{layout.columns.length()}",
    )
  }
  let col = if columns == 0 { 1 } else { layout.columns[0].1 + columns }
  guard col > 1 || layout.body_first > 1 else {
    raise schema_error(
      file~,
      "freeze at layout '\{name}' would freeze nothing: it starts at A1 with no header, and 'columns' is 0",
    )
  }
  @units.CellRef(col~, row=layout.body_first)
}

///|
/// A sheet's `split: { x, y }` — a draggable splitter, each axis given in
/// points from the top-left corner and defaulting to `0` (that axis unsplit).
/// Splitting on neither axis is a mistake worth reporting.
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
