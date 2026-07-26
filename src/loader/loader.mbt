///|
/// Load a parsed YAML document into a workbook model, validating the schema. The
/// spec is a mapping with a `sheets` sequence plus optional top-level `active`
/// (the sheet Excel opens on), `params` (named values with defaults, substituted
/// as `${name}` and overridable through `params~` — see `substitute_params`),
/// `date1904` (the 1904 date system), `default_font` (the workbook default font
/// face), and `defs` (named definitions — see `load_defs`). Sheets appear in Excel in declaration order. Each sheet has a
/// `name` and optional `cells` (an A1-reference mapping), `data` (external CSV /
/// JSON tables — see `load_data`), `merges`, `columns` / `rows` (bands carrying
/// a default style, a size, visibility, and outline grouping — see
/// `load_columns`), the presentation keys `visibility`, `freeze` / `split`,
/// `gridlines`, and `tab_color`, and a `print:` block (see `load_page_setup`).
/// A cell value is a scalar shorthand or an expanded mapping with a `value`,
/// `formula`, or `rich` run list, plus optional `type`, `format`, and `style`
/// (see `load_cell`). A style is referenced by bareword name and a value/formula
/// by `{ $ref: name }` (ADR-012). Any node may instead be `{ $include: path }`,
/// read through `resolve` (ADR-014).
///
/// Sheet keys apply in the order written, so where a `data:` table and `cells:`
/// overlap, whichever comes last wins.
///
/// ```yaml
/// default_font: Calibri
/// active: Sheet1
/// params:
///   region: APAC
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
///     data:
///       - at: A3
///         csv: data/sales.csv
///     print:
///       area: A1:D50
///       orientation: landscape
///       fit: { width: 1 }
///       header: "&C&\"Arial,Bold\"Quarterly report"
///   - name: "${region} scratch"
///     visibility: hidden
/// ```
///
/// Unknown keys, wrong types, bad cell references, and dangling name references
/// are `@diag.SchemaError`s (ADR-006). `file` names the source in those
/// diagnostics.
pub fn load(
  document : @yaml.Node,
  file~ : String,
  resolve? : IncludeResolver = no_includes,
  params? : Map[String, String] = Map([]),
) -> @model.Workbook raise {
  // Two pre-passes collapse a multi-file, parameterized spec into the single
  // plain tree every reader below sees (ADR-005, ADR-014). Includes expand
  // first, so an included file may use the parameters too.
  let document = expand_includes(document, file~, resolve~, chain=[file])
  let document = substitute_params(document, file~, overrides=params)
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
        load_sheets(value, workbook, file~, defs~, resolve~)
      }
      "date1904" => () // consumed by read_date_system
      "default_font" => () // consumed by read_default_font
      "defs" => () // consumed by load_defs
      "active" => () // resolved below, once every sheet name is known
      "params" => () // consumed by the substitution pass
      _ =>
        raise schema_error(
          file~,
          "unknown top-level key '\{key}' (expected 'sheets', 'active', 'params', 'date1904', 'default_font', or 'defs')",
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
fn load_sheets(
  node : @yaml.Node,
  workbook : @model.Workbook,
  file~ : String,
  defs~ : Defs,
  resolve~ : IncludeResolver,
) -> Unit raise {
  let items = expect_seq(node, file~, context="'sheets'")
  let seen_names = []
  for item in items {
    let name = load_sheet(item, workbook, file~, defs~, resolve~)
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
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet (expected 'name', 'cells', 'data', 'columns', 'rows', 'merges', 'visibility', 'freeze', 'split', 'gridlines', 'tab_color', or 'print')",
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
  let corner = "\{what} '\{text}'"
  let first = expect_cell_ref(left.to_owned(), file~, what=corner)
  let second = expect_cell_ref(right.to_owned(), file~, what=corner)
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
    let cell = expect_cell_ref(reference, file~)
    let (value, style) = load_cell(value_node, file~, reference~, defs~)
    sheet.set(cell, value, style?)
  }
}
