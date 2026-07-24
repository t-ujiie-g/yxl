///|
/// Load a parsed YAML document into a workbook model, validating the schema. The
/// spec is a mapping with a `sheets` sequence plus optional top-level `active`
/// (the sheet Excel opens on), `date1904` (the 1904 date system), `default_font`
/// (the workbook default font face), and `defs` (named definitions — see
/// `load_defs`). Sheets appear in Excel in declaration order. Each sheet has a
/// `name` and optional `cells` (an A1-reference mapping), `merges`, `columns` /
/// `rows` (bands carrying a default style, a size, visibility, and outline
/// grouping — see `load_columns`), the presentation keys `visibility`,
/// `freeze` / `split`, `gridlines`, and `tab_color`, and a `print:` block (see
/// `load_page_setup`). A cell value is a
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
///     freeze: B2
///     gridlines: false
///     tab_color: "1F77B4"
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
///     print:
///       area: A1:D50
///       orientation: landscape
///       fit: { width: 1 }
///       header: "&C&\"Arial,Bold\"Quarterly report"
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
  let mut freeze = None
  let mut split = None
  let mut gridlines = None
  let mut tab_color = None
  let mut page = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "name" => name = Some(expect_string(value, file~, context="sheet 'name'"))
      "cells" => cells = Some(value)
      "columns" => columns = Some(value)
      "rows" => rows = Some(value)
      "merges" => merges = Some(value)
      "visibility" => visibility = load_visibility(value, file~)
      "freeze" => freeze = Some(load_freeze(value, file~))
      "split" => split = Some(load_split(value, file~))
      "gridlines" =>
        gridlines = Some(expect_bool(value, file~, context="sheet 'gridlines'"))
      "tab_color" =>
        tab_color = Some(
          expect_color(value, file~, what="'tab_color'", context="sheet"),
        )
      "print" => page = Some(load_page_setup(value, file~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet (expected 'name', 'cells', 'columns', 'rows', 'merges', 'visibility', 'freeze', 'split', 'gridlines', 'tab_color', or 'print')",
        )
    }
  }
  guard name is Some(sheet_name) else {
    raise schema_error(file~, "a sheet is missing required key 'name'")
  }
  guard !(freeze is Some(_) && split is Some(_)) else {
    raise schema_error(
      file~,
      "sheet '\{sheet_name}' cannot combine 'freeze' and 'split'",
    )
  }
  let sheet = workbook.add_sheet(sheet_name, visibility~)
  // At most one of the two is set; the guard above rejected both.
  match (freeze, split) {
    (Some(panes), _) | (_, Some(panes)) => sheet.set_panes(panes)
    (None, None) => ()
  }
  if gridlines is Some(shown) {
    sheet.set_gridlines(shown)
  }
  if tab_color is Some(color) {
    sheet.set_tab_color(color)
  }
  if page is Some(page) {
    sheet.set_page_setup(page)
  }
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
/// A sheet's `freeze: <cell>` — the rows above and columns left of that cell
/// stay put while the rest scrolls. `A1` freezes nothing, so it is a mistake
/// worth reporting rather than a no-op.
fn load_freeze(
  node : @yaml.Node,
  file~ : String,
) -> @model.Panes raise @diag.SchemaError {
  let reference = expect_string(node, file~, context="sheet 'freeze'")
  guard @units.CellRef::parse_a1(reference) is Some(cell) else {
    raise schema_error(
      file~,
      "'\{reference}' is not a valid A1 cell reference in 'freeze'",
    )
  }
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

///|
/// A sheet's `print:` block — how it goes onto paper. Every key is optional:
/// `area` (a range), `orientation`, `margins`, `scale` or `fit` (Excel offers
/// one or the other, never both), `header` / `footer`, and `breaks`.
fn load_page_setup(
  node : @yaml.Node,
  file~ : String,
) -> @model.PageSetup raise @diag.SchemaError {
  let mut page = @model.PageSetup::empty()
  let mut seen_scale = false
  let mut seen_fit = false
  for entry in expect_map(node, file~, context="sheet 'print'") {
    let (key, value) = entry
    match key {
      "area" =>
        page = {
          ..page,
          area: Some(
            parse_range(
              expect_string(value, file~, context="print 'area'"),
              file~,
              what="print area",
            ),
          ),
        }
      "orientation" =>
        page = { ..page, orientation: Some(load_orientation(value, file~)) }
      "margins" => page = { ..page, margins: Some(load_margins(value, file~)) }
      "scale" => {
        seen_scale = true
        page = { ..page, scale: Some(load_scale(value, file~)) }
      }
      "fit" => {
        seen_fit = true
        page = { ..page, scale: Some(load_fit(value, file~)) }
      }
      "header" =>
        page = {
          ..page,
          header: Some(expect_string(value, file~, context="print 'header'")),
        }
      "footer" =>
        page = {
          ..page,
          footer: Some(expect_string(value, file~, context="print 'footer'")),
        }
      "breaks" => page = { ..page, breaks: load_breaks(value, file~) }
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet 'print' (expected 'area', 'orientation', 'margins', 'scale', 'fit', 'header', 'footer', or 'breaks')",
        )
    }
  }
  guard !(seen_scale && seen_fit) else {
    raise schema_error(
      file~,
      "sheet 'print' cannot combine 'scale' and 'fit' (Excel scales by one or the other)",
    )
  }
  page
}

///|
/// A `print.orientation:` — which way the paper runs.
fn load_orientation(
  node : @yaml.Node,
  file~ : String,
) -> @model.Orientation raise @diag.SchemaError {
  match expect_string(node, file~, context="print 'orientation'") {
    "portrait" => Portrait
    "landscape" => Landscape
    other =>
      raise schema_error(
        file~,
        "unknown print orientation '\{other}' (expected 'portrait' or 'landscape')",
      )
  }
}

///|
/// A `print.scale:` percentage of actual size, within Excel's range.
fn load_scale(
  node : @yaml.Node,
  file~ : String,
) -> @model.PageScale raise @diag.SchemaError {
  guard node is @yaml.Int(percent) else {
    raise schema_error(file~, "print 'scale' must be a whole number of percent")
  }
  guard percent >= @model.min_page_scale.to_int64() &&
    percent <= @model.max_page_scale.to_int64() else {
    raise schema_error(
      file~,
      "print 'scale' must be between \{@model.min_page_scale} and \{@model.max_page_scale} percent",
    )
  }
  Percent(percent.to_int())
}

///|
/// A `print.fit: { width, height }` — how many pages across and down the sheet
/// is shrunk to fit. An axis left out (or `0`) is unconstrained; constraining
/// neither would scale nothing.
fn load_fit(
  node : @yaml.Node,
  file~ : String,
) -> @model.PageScale raise @diag.SchemaError {
  let mut width = 0
  let mut height = 0
  for entry in expect_map(node, file~, context="print 'fit'") {
    let (key, value) = entry
    match key {
      "width" => width = expect_page_count(value, file~, what="width")
      "height" => height = expect_page_count(value, file~, what="height")
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in print 'fit' (expected 'width' or 'height')",
        )
    }
  }
  guard width > 0 || height > 0 else {
    raise schema_error(
      file~,
      "print 'fit' needs a non-zero 'width' or 'height' (in pages)",
    )
  }
  Fit(width~, height~)
}

///|
/// A page count in a `fit` axis: a whole number of pages, never negative.
fn expect_page_count(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> Int raise @diag.SchemaError {
  guard node is @yaml.Int(pages) && pages >= 0L else {
    raise schema_error(
      file~,
      "print 'fit' \{what} must be a whole number of pages (0 for unconstrained)",
    )
  }
  pages.to_int()
}

///|
/// A `print.margins:` mapping, in inches — Excel's unit for these. A negative
/// margin is meaningless, so it is a diagnostic.
fn load_margins(
  node : @yaml.Node,
  file~ : String,
) -> @model.PageMargins raise @diag.SchemaError {
  let mut margins : @model.PageMargins = {
    top: None,
    bottom: None,
    left: None,
    right: None,
    header: None,
    footer: None,
  }
  for entry in expect_map(node, file~, context="print 'margins'") {
    let (key, value) = entry
    let inches = expect_number(value, file~, context="print margin '\{key}'")
    guard inches >= 0.0 else {
      raise schema_error(file~, "print margin '\{key}' cannot be negative")
    }
    match key {
      "top" => margins = { ..margins, top: Some(inches) }
      "bottom" => margins = { ..margins, bottom: Some(inches) }
      "left" => margins = { ..margins, left: Some(inches) }
      "right" => margins = { ..margins, right: Some(inches) }
      "header" => margins = { ..margins, header: Some(inches) }
      "footer" => margins = { ..margins, footer: Some(inches) }
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in print 'margins' (expected 'top', 'bottom', 'left', 'right', 'header', or 'footer')",
        )
    }
  }
  margins
}

///|
/// A `print.breaks:` sequence of cells, each starting a new page above and to
/// the left of itself. `A1` starts no page, so it is a mistake worth reporting.
fn load_breaks(
  node : @yaml.Node,
  file~ : String,
) -> Array[@units.CellRef] raise @diag.SchemaError {
  let breaks = []
  for item in expect_seq(node, file~, context="print 'breaks'") {
    let reference = expect_string(item, file~, context="a print break")
    guard @units.CellRef::parse_a1(reference) is Some(cell) else {
      raise schema_error(
        file~,
        "'\{reference}' is not a valid A1 cell reference in print 'breaks'",
      )
    }
    guard cell.col > 1 || cell.row > 1 else {
      raise schema_error(file~, "a print break at 'A1' would break nothing")
    }
    breaks.push(cell)
  }
  breaks
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
/// Parse a `TopLeft:BottomRight` range string (e.g. `A1:B2`) into a canonical
/// range — corners may be given in any order. `what` names the range's role in
/// the diagnostics (e.g. `"merge range"`).
fn parse_range(
  text : String,
  file~ : String,
  what~ : String,
) -> @model.CellRange raise @diag.SchemaError {
  guard text.split_once(":") is Some((left, right)) else {
    raise schema_error(file~, "\{what} '\{text}' must be 'TopLeft:BottomRight'")
  }
  guard @units.CellRef::parse_a1(left.to_owned()) is Some(first) else {
    raise schema_error(
      file~,
      "'\{left}' is not a valid A1 cell reference in \{what} '\{text}'",
    )
  }
  guard @units.CellRef::parse_a1(right.to_owned()) is Some(second) else {
    raise schema_error(
      file~,
      "'\{right}' is not a valid A1 cell reference in \{what} '\{text}'",
    )
  }
  let (top_left, bottom_right) = @units.CellRef::rect(first, second)
  { top_left, bottom_right }
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
