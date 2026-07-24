///|
/// Load a parsed YAML document into a workbook model, validating the schema. The
/// spec is a mapping with a `sheets` sequence plus optional top-level `active`
/// (the sheet Excel opens on), `date1904` (the 1904 date system), `default_font`
/// (the workbook default font face), and `defs` (named definitions — see
/// `load_defs`). Sheets appear in Excel in declaration order. Each sheet has a
/// `name` and optional `visibility`, `cells` (an A1-reference mapping),
/// `merges`, and `columns` / `rows` (bands carrying a default style, a size,
/// visibility, and outline grouping — see `load_columns`). A cell value is a
/// scalar shorthand or an expanded mapping with a `value`, `formula`, or `rich`
/// run list, plus optional `type`, `format`, and `style` (see `load_cell`). A
/// style is referenced by bareword name and a value/formula by `{ $ref: name }`
/// (ADR-012).
///
/// ```yaml
/// default_font: Calibri
/// active: Sheet1
/// defs:
///   styles:
///     header: { font: { bold: true } }
///   values:
///     company: "Acme Corp"
/// sheets:
///   - name: Sheet1
///     columns:
///       - at: B
///         style: header
///       - at: D-F
///         group: 1
///         hidden: true
///     cells:
///       A1: { $ref: company }
///       B1: { value: 0.5, format: "0.00%", style: header }
///       C1: { formula: "SUM(B1:B1)", style: { font: { italic: true } } }
///       D1: { rich: ["plain ", { text: bold, font: { bold: true } }] }
///   - name: Scratch
///     visibility: hidden
/// ```
///
/// Unknown keys, wrong types, bad cell references, and dangling name references
/// are `@diag.SchemaError`s (ADR-006). `file` names the source in those
/// diagnostics.
pub fn load(
  document : @yaml.Node,
  file~ : String,
) -> @model.Workbook raise @diag.SchemaError {
  let root = expect_map(document, file~, context="the top level")
  let workbook = @model.Workbook::new(
    date_system=read_date_system(root, file~),
    default_font?=read_default_font(root, file~),
  )
  // Registers each declared value/formula as a workbook defined name (ADR-013).
  let defs = load_defs(root, workbook, file~)
  let mut seen_sheets = false
  for entry in root {
    let (key, value) = entry
    match key {
      "sheets" => {
        seen_sheets = true
        load_sheets(value, workbook, file~, defs~)
      }
      "date1904" => () // consumed by read_date_system
      "default_font" => () // consumed by read_default_font
      "defs" => () // consumed by load_defs
      "active" => () // resolved below, once every sheet name is known
      _ =>
        raise schema_error(
          file~,
          "unknown top-level key '\{key}' (expected 'sheets', 'active', 'date1904', 'default_font', or 'defs')",
        )
    }
  }
  guard seen_sheets else {
    raise schema_error(file~, "missing required key 'sheets'")
  }
  read_active_sheet(root, workbook, file~)
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
  guard workbook.sheets.iter().find_first(sheet => sheet.name == name)
    is Some(sheet) else {
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
  match find_key(root, "default_font") {
    Some(value) => Some(expect_string(value, file~, context="'default_font'"))
    None => None
  }
}

///|
/// The value of the first `key` entry in a mapping's entries, or `None`.
fn find_key(root : Array[(String, @yaml.Node)], key : String) -> @yaml.Node? {
  for entry in root {
    let (candidate, value) = entry
    if candidate == key {
      return Some(value)
    }
  }
  None
}

///|
fn load_sheets(
  node : @yaml.Node,
  workbook : @model.Workbook,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  let items = expect_seq(node, file~, context="'sheets'")
  let seen_names = []
  for item in items {
    let name = load_sheet(item, workbook, file~, defs~)
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
) -> String raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a sheet")
  let mut name = None
  let mut cells = None
  let mut columns = None
  let mut rows = None
  let mut merges = None
  let mut visibility = @model.Visible
  for entry in entries {
    let (key, value) = entry
    match key {
      "name" => name = Some(expect_string(value, file~, context="sheet 'name'"))
      "cells" => cells = Some(value)
      "columns" => columns = Some(value)
      "rows" => rows = Some(value)
      "merges" => merges = Some(value)
      "visibility" => visibility = load_visibility(value, file~)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet (expected 'name', 'cells', 'columns', 'rows', 'merges', or 'visibility')",
        )
    }
  }
  guard name is Some(sheet_name) else {
    raise schema_error(file~, "a sheet is missing required key 'name'")
  }
  let sheet = workbook.add_sheet(sheet_name, visibility~)
  if columns is Some(columns_node) {
    load_columns(columns_node, sheet, file~, defs~)
  }
  if rows is Some(rows_node) {
    load_rows(rows_node, sheet, file~, defs~)
  }
  if cells is Some(cells_node) {
    load_cells(cells_node, sheet, file~, defs~)
  }
  if merges is Some(merges_node) {
    load_merges(merges_node, sheet, file~)
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
/// Load a sheet's `merges:` sequence: each entry is a range string
/// `TopLeft:BottomRight` (e.g. `A1:B2`) merged into one cell. Corners may be
/// given in any order; the model canonicalizes them.
fn load_merges(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'merges'") {
    let range = expect_string(item, file~, context="a merge range")
    guard range.split_once(":") is Some((left, right)) else {
      raise schema_error(
        file~,
        "merge range '\{range}' must be 'TopLeft:BottomRight'",
      )
    }
    guard @units.CellRef::parse_a1(left.to_owned()) is Some(top_left) else {
      raise schema_error(
        file~,
        "'\{left}' is not a valid A1 cell reference in merge range '\{range}'",
      )
    }
    guard @units.CellRef::parse_a1(right.to_owned()) is Some(bottom_right) else {
      raise schema_error(
        file~,
        "'\{right}' is not a valid A1 cell reference in merge range '\{range}'",
      )
    }
    sheet.merge(top_left, bottom_right)
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
    guard @units.CellRef::parse_a1(reference) is Some(cell) else {
      raise schema_error(
        file~,
        "'\{reference}' is not a valid A1 cell reference",
      )
    }
    let (value, style) = load_cell(value_node, file~, reference~, defs~)
    sheet.set(cell, value, style?)
  }
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
fn schema_error(file~ : String, message : String) -> @diag.SchemaError {
  @diag.SchemaError(@diag.Diagnostic::new("\{file}: \{message}"))
}
