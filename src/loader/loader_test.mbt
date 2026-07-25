///|
/// Parse then load, returning the diagnostic message if loading fails. `files`
/// backs any `$include` in the source.
fn schema_message(
  source : String,
  files? : Map[String, String] = Map([]),
) -> String? raise {
  let document = @yaml.parse(source, file="spec.yaml")
  try {
    @loader.load(document, file="spec.yaml", resolve=memory_files(files))
    |> ignore
    None
  } catch {
    @diag.SchemaError(d) | @diag.YamlError(d) => Some(d.render())
    other => Some(other.to_string())
  }
}

///|
/// Parse then load a spec expected to be valid. `files` backs any `$include`.
fn load_ok(
  source : String,
  files? : Map[String, String] = Map([]),
) -> @model.Workbook raise {
  @loader.load(
    @yaml.parse(source, file="spec.yaml"),
    file="spec.yaml",
    resolve=memory_files(files),
  )
}

///|
/// An include resolver over an in-memory file map: the loader resolves includes
/// without touching the disk (ADR-003), so these tests need no fixtures.
fn memory_files(files : Map[String, String]) -> @loader.IncludeResolver {
  (_from, path) => {
    match files.get(path) {
      Some(source) => { name: path, source }
      None =>
        raise @diag.SchemaError(
          @diag.Diagnostic::new("no such included file '\{path}'"),
        )
    }
  }
}

///|
test "load parses a `type: date` cell with a default date format" {
  let workbook = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { value: \"2026-07-23\", type: date }\n",
  )
  let cell = workbook.sheets[0].cells[0]
  assert_eq(
    cell.value,
    @model.Date(@units.DateTime::{
      year: 2026,
      month: 7,
      day: 23,
      hour: 0,
      minute: 0,
      second: 0,
    }),
  )
  assert_eq(cell.style, Some(@model.Style::number_format("yyyy-mm-dd")))
}

///|
test "a date-time value defaults to a date-time format, and format overrides" {
  let datetime = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { value: \"2026-07-23 14:30:00\", type: date }\n",
  )
  assert_eq(
    datetime.sheets[0].cells[0].style,
    Some(@model.Style::number_format("yyyy-mm-dd hh:mm:ss")),
  )
  let custom = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { value: \"2026-07-23\", type: date, format: \"mmm d\" }\n",
  )
  assert_eq(
    custom.sheets[0].cells[0].style,
    Some(@model.Style::number_format("mmm d")),
  )
}

///|
test "the date1904 top-level key selects the 1904 date system" {
  assert_eq(
    load_ok("sheets:\n  - name: S\ndate1904: true\n").date_system,
    Date1904,
  )
  assert_eq(load_ok("sheets:\n  - name: S\n").date_system, Date1900)
}

///|
test "load rejects a non-boolean date1904 value" {
  assert_eq(
    schema_message("sheets:\n  - name: S\ndate1904: yes\n"),
    Some("spec.yaml: 'date1904' must be true or false"),
  )
}

///|
test "load rejects invalid dates and unknown cell types" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: \"2026-13-01\", type: date }\n",
    ),
    Some("spec.yaml: cell 'A1' is not a valid date: '2026-13-01'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, type: money }\n",
    ),
    Some(
      "spec.yaml: unknown type 'money' for cell 'A1' (expected 'text', 'number', 'bool', 'date', or 'error')",
    ),
  )
}

///|
test "load parses a formula cell, stripping a leading '=', with a cached value" {
  let plain = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { formula: \"=SUM(B1:B2)\" }\n",
  )
  assert_eq(
    plain.sheets[0].cells[0].value,
    @model.Formula(formula="SUM(B1:B2)", cached=None),
  )
  let cached = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { formula: \"B1*2\", value: 84 }\n",
  )
  assert_eq(
    cached.sheets[0].cells[0].value,
    @model.Formula(formula="B1*2", cached=Some(@model.Number(84.0))),
  )
}

///|
test "load rejects combining a formula with a type" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { formula: \"A2\", type: date }\n",
    ),
    Some("spec.yaml: cell 'A1' cannot combine 'formula' and 'type'"),
  )
}

///|
test "explicit typing coerces values to the declared type" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: 42, type: text }
      #|      A2: { value: "42", type: number }
      #|      A3: { value: "true", type: bool }
      #|      A4: { value: true, type: text }
      #|
    ),
  )
  let cells = workbook.sheets[0].cells
  assert_eq(cells[0].value, @model.Text("42"))
  assert_eq(cells[1].value, @model.Number(42.0))
  assert_eq(cells[2].value, @model.Bool(true))
  assert_eq(cells[3].value, @model.Text("true"))
}

///|
test "an error literal is validated against the known Excel errors" {
  let workbook = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { value: \"#DIV/0!\", type: error }\n",
  )
  assert_eq(workbook.sheets[0].cells[0].value, @model.Error("#DIV/0!"))
}

///|
test "load rejects bad coercions and unknown error literals" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: \"abc\", type: number }\n",
    ),
    Some("spec.yaml: cell 'A1' value is not a number: 'abc'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: \"yes\", type: bool }\n",
    ),
    Some("spec.yaml: cell 'A1' value is not a boolean (true or false)"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: \"#OOPS\", type: error }\n",
    ),
    Some("spec.yaml: cell 'A1' is not a valid Excel error literal: '#OOPS'"),
  )
}

///|
test "load builds sheets and typed cells from a minimal spec" {
  let source =
    #|sheets:
    #|  - name: Sheet1
    #|    cells:
    #|      A1: hello
    #|      B1: 42
    #|      C1: true
    #|      D1: 3.5
    #|  - name: Second
    #|    cells:
    #|      A1: "42"
    #|
  let workbook = @loader.load(
    @yaml.parse(source, file="spec.yaml"),
    file="spec.yaml",
  )
  @debug.debug_inspect(
    workbook,
    content=(
      #|{
      #|  sheets: [
      #|    {
      #|      name: "Sheet1",
      #|      cells: [
      #|        { pos: { col: 1, row: 1 }, value: Text("hello"), style: None },
      #|        { pos: { col: 2, row: 1 }, value: Number(42), style: None },
      #|        { pos: { col: 3, row: 1 }, value: Bool(true), style: None },
      #|        { pos: { col: 4, row: 1 }, value: Number(3.5), style: None },
      #|      ],
      #|      columns: [],
      #|      rows: [],
      #|      merges: [],
      #|      visibility: Visible,
      #|      page: None,
      #|      panes: None,
      #|      gridlines: None,
      #|      tab_color: None,
      #|    },
      #|    {
      #|      name: "Second",
      #|      cells: [{ pos: { col: 1, row: 1 }, value: Text("42"), style: None }],
      #|      columns: [],
      #|      rows: [],
      #|      merges: [],
      #|      visibility: Visible,
      #|      page: None,
      #|      panes: None,
      #|      gridlines: None,
      #|      tab_color: None,
      #|    },
      #|  ],
      #|  date_system: Date1900,
      #|  default_font: None,
      #|  defined_names: [],
      #|  active_sheet: None,
      #|}
    ),
  )
}

///|
test "load accepts the expanded cell form with a number format" {
  let source =
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: { value: 0.5, format: "0.00%" }
    #|      B1: 42
    #|
  let workbook = @loader.load(
    @yaml.parse(source, file="spec.yaml"),
    file="spec.yaml",
  )
  let cells = workbook.sheets[0].cells
  assert_eq(cells[0].value, @model.Number(0.5))
  assert_eq(cells[0].style, Some(@model.Style::number_format("0.00%")))
  // A plain scalar cell keeps the General format.
  assert_eq(cells[1].value, @model.Number(42.0))
  assert_eq(cells[1].style, None)
}

///|
test "load parses a full style: font, fill, border, alignment, and number format" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1:
      #|        value: 0.5
      #|        format: "0.00%"
      #|        style:
      #|          font: { bold: true, size: 12, name: Calibri, color: "FF0000" }
      #|          fill: "FFFF00"
      #|          align: { horizontal: center, vertical: middle, wrap: true }
      #|          border:
      #|            all: thin
      #|            bottom: { style: double, color: "000000" }
      #|
    ),
  )
  assert_eq(
    workbook.sheets[0].cells[0].style,
    Some(@model.Style::{
      number_format: Some("0.00%"),
      font: Some({
        bold: Some(true),
        italic: None,
        underline: None,
        strike: None,
        size: Some(12.0),
        name: Some("Calibri"),
        color: @units.Color::parse("FF0000"),
      }),
      fill: Some({ color: @units.Color::parse("FFFF00").unwrap() }),
      align: Some({
        horizontal: Some(Center),
        vertical: Some(Middle),
        wrap: Some(true),
      }),
      borders: Some({
        left: Some({ style: Thin, color: None }),
        right: Some({ style: Thin, color: None }),
        top: Some({ style: Thin, color: None }),
        bottom: Some({ style: Double, color: @units.Color::parse("000000") }),
      }),
    }),
  )
}

///|
test "load accepts a fill and border shorthand" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: 1, style: { fill: { color: "00FF00" }, border: medium } }
      #|
    ),
  )
  let style = workbook.sheets[0].cells[0].style.unwrap()
  assert_eq(style.fill, Some({ color: @units.Color::parse("00FF00").unwrap() }))
  assert_eq(
    style.borders,
    Some({
      left: Some({ style: Medium, color: None }),
      right: Some({ style: Medium, color: None }),
      top: Some({ style: Medium, color: None }),
      bottom: Some({ style: Medium, color: None }),
    }),
  )
}

///|
test "load rejects invalid style attributes" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { fill: \"red\" } }\n",
    ),
    Some("spec.yaml: cell 'A1' fill is not a valid hex color: 'red'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { align: { horizontal: middle } } }\n",
    ),
    Some(
      "spec.yaml: cell 'A1' has an unknown horizontal alignment 'middle' (expected 'left', 'center', 'right', 'fill', 'justify', or 'distributed')",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { border: wavy } }\n",
    ),
    Some(
      "spec.yaml: cell 'A1' has an unknown border style 'wavy' (expected 'thin', 'medium', 'thick', 'dashed', 'dotted', 'double', or 'hair')",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { glow: true } }\n",
    ),
    Some(
      "spec.yaml: unknown key 'glow' in cell 'A1' style (expected 'font', 'fill', 'border', or 'align')",
    ),
  )
}

///|
test "load parses a rich-text cell of plain and fonted runs" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1:
      #|        rich:
      #|          - "Plain "
      #|          - { text: "bold red", font: { bold: true, color: "FF0000" } }
      #|        style:
      #|          align: { wrap: true }
      #|
    ),
  )
  let cell = workbook.sheets[0].cells[0]
  assert_eq(
    cell.value,
    @model.RichText([
      { text: "Plain ", font: None },
      {
        text: "bold red",
        font: Some({
          bold: Some(true),
          italic: None,
          underline: None,
          strike: None,
          size: None,
          name: None,
          color: @units.Color::parse("FF0000"),
        }),
      },
    ]),
  )
  // A rich-text cell may still carry a cell style (here, wrapping).
  assert_eq(
    cell.style,
    Some(@model.Style::{
      ..@model.Style::empty(),
      align: Some({ horizontal: None, vertical: None, wrap: Some(true) }),
    }),
  )
}

///|
test "load rejects rich text combined with a value, and an empty run list" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { rich: [\"a\"], value: 1 }\n",
    ),
    Some("spec.yaml: cell 'A1' cannot combine 'rich' and 'value'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    cells:\n      A1: { rich: [] }\n"),
    Some("spec.yaml: cell 'A1' rich text needs at least one run"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { rich: [{ font: { bold: true } }] }\n",
    ),
    Some("spec.yaml: cell 'A1' rich text run needs a 'text'"),
  )
}

///|
test "load parses column/row default styles and the workbook default font" {
  let workbook = load_ok(
    (
      #|default_font: Calibri
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: B
      #|        style: { font: { bold: true } }
      #|      - at: D-F
      #|        format: "0.00"
      #|    rows:
      #|      - at: 1
      #|        style: { fill: "DDDDDD" }
      #|      - at: 2-3
      #|        style: { align: { horizontal: right } }
      #|
    ),
  )
  assert_eq(workbook.default_font, Some("Calibri"))
  let sheet = workbook.sheets[0]
  // Column B is bold; D-F share one number-format band.
  assert_eq(sheet.columns.length(), 2)
  assert_eq(sheet.columns[0].first, 2)
  assert_eq(sheet.columns[0].last, 2)
  assert_eq(sheet.columns[0].style.unwrap().font.unwrap().bold, Some(true))
  assert_eq(sheet.columns[1].first, 4)
  assert_eq(sheet.columns[1].last, 6)
  assert_eq(sheet.columns[1].style.unwrap().number_format, Some("0.00"))
  // Row 1 filled; rows 2-3 right-aligned as one band.
  assert_eq(sheet.rows.length(), 2)
  assert_eq((sheet.rows[0].first, sheet.rows[0].last), (1, 1))
  assert_eq((sheet.rows[1].first, sheet.rows[1].last), (2, 3))
  assert_eq(sheet.rows[1].style.unwrap().align.unwrap().horizontal, Some(Right))
}

///|
test "load rejects invalid column/row selectors and a missing 'at', and keeps empty bands out" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: A1\n        style: { font: { bold: true } }\n",
    ),
    Some("spec.yaml: 'A1' is not a valid column"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: F-D\n        format: \"0\"\n",
    ),
    Some("spec.yaml: column range 'F-D' is reversed"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    rows:\n      - at: 0\n        format: \"0\"\n",
    ),
    Some("spec.yaml: '0' is not a valid row"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    rows:\n      - format: \"0\"\n"),
    Some("spec.yaml: a row entry is missing required key 'at'"),
  )
  // An empty band spec adds no band rather than erroring.
  let workbook = load_ok("sheets:\n  - name: S\n    columns:\n      - at: B\n")
  assert_eq(workbook.sheets[0].columns.length(), 0)
}

///|
test "load parses merges, column widths, and row heights" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: B
      #|        width: 18
      #|      - at: D-F
      #|        style: { font: { bold: true } }
      #|        width: 10
      #|    rows:
      #|      - at: 1
      #|        height: 24
      #|    merges:
      #|      - A1:C1
      #|      - B2:B4
      #|
    ),
  )
  let sheet = workbook.sheets[0]
  // Column B has just a width; D-F carries a style and a width on one band.
  assert_eq(sheet.columns.length(), 2)
  assert_eq((sheet.columns[0].first, sheet.columns[0].last), (2, 2))
  assert_eq(sheet.columns[0].size, Some(18.0))
  assert_eq(sheet.columns[0].style, None)
  assert_eq((sheet.columns[1].first, sheet.columns[1].last), (4, 6))
  assert_eq(sheet.columns[1].size, Some(10.0))
  assert_true(sheet.columns[1].style is Some(_))
  assert_eq(sheet.rows.length(), 1)
  assert_eq(sheet.rows[0].size, Some(24.0))
  assert_eq(sheet.merges, [
    {
      top_left: @units.CellRef::new(col=1, row=1),
      bottom_right: @units.CellRef::new(col=3, row=1),
    },
    {
      top_left: @units.CellRef::new(col=2, row=2),
      bottom_right: @units.CellRef::new(col=2, row=4),
    },
  ])
}

///|
test "a merge range's corners are canonicalized regardless of order" {
  let workbook = load_ok("sheets:\n  - name: S\n    merges:\n      - C3:A1\n")
  assert_eq(workbook.sheets[0].merges, [
    {
      top_left: @units.CellRef::new(col=1, row=1),
      bottom_right: @units.CellRef::new(col=3, row=3),
    },
  ])
}

///|
test "load rejects bad merge ranges and a size key on the wrong axis" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    merges:\n      - A1\n"),
    Some("spec.yaml: merge range 'A1' must be 'TopLeft:BottomRight'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    merges:\n      - A1:Z0\n"),
    Some(
      "spec.yaml: 'Z0' is not a valid A1 cell reference in merge range 'A1:Z0'",
    ),
  )
  // `width` belongs on a column band, `height` on a row band.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    rows:\n      - at: 1\n        width: 10\n",
    ),
    Some(
      "spec.yaml: unknown key 'width' in row '1' (expected 'at', 'style', 'format', 'height', 'hidden', or 'group')",
    ),
  )
}

///|
test "load parses band visibility and outline grouping" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: B-C
      #|        group: 1
      #|        hidden: true
      #|      - at: D
      #|        width: 12
      #|        group: 0
      #|    rows:
      #|      - at: 2-4
      #|        group: 2
      #|        hidden: false
      #|
    ),
  )
  let sheet = workbook.sheets[0]
  // A collapsed group: the band is both grouped and hidden.
  assert_eq(sheet.columns[0], {
    first: 2,
    last: 3,
    style: None,
    size: None,
    hidden: Some(true),
    outline_level: Some(1),
  })
  // Grouping and sizing coexist on one band; `group: 0` is "ungrouped", which is
  // distinct from leaving the key out.
  assert_eq(sheet.columns[1], {
    first: 4,
    last: 4,
    style: None,
    size: Some(12.0),
    hidden: None,
    outline_level: Some(0),
  })
  assert_eq(sheet.rows[0], {
    first: 2,
    last: 4,
    style: None,
    size: None,
    hidden: Some(false),
    outline_level: Some(2),
  })
}

///|
test "load rejects a bad 'hidden' flag and an out-of-range or fractional 'group'" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: B\n        hidden: yes please\n",
    ),
    Some("spec.yaml: column 'B' hidden must be true or false"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    rows:\n      - at: 1\n        group: 8\n",
    ),
    Some("spec.yaml: row '1' group must be between 0 and 7"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    rows:\n      - at: 1\n        group: -1\n",
    ),
    Some("spec.yaml: row '1' group must be between 0 and 7"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: B\n        group: 1.5\n",
    ),
    Some("spec.yaml: column 'B' group must be a whole number"),
  )
}

///|
test "load rejects an expanded cell missing its value" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { format: \"0%\" }\n",
    ),
    Some("spec.yaml: cell 'A1' needs a 'value' or a 'formula'"),
  )
}

///|
test "load rejects an unknown key in an expanded cell" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, color: red }\n",
    ),
    Some(
      "spec.yaml: unknown key 'color' in cell 'A1' (expected 'value', 'formula', 'rich', 'type', 'format', or 'style')",
    ),
  )
}

///|
test "load rejects an unknown top-level key" {
  assert_eq(
    schema_message("sheetz:\n  - name: S\n"),
    Some(
      "spec.yaml: unknown top-level key 'sheetz' (expected 'sheets', 'active', 'date1904', 'default_font', or 'defs')",
    ),
  )
}

///|
test "load requires the sheets key" {
  assert_eq(
    schema_message("title: report\n"),
    Some(
      "spec.yaml: unknown top-level key 'title' (expected 'sheets', 'active', 'date1904', 'default_font', or 'defs')",
    ),
  )
  assert_eq(
    schema_message("{}\n"),
    Some("spec.yaml: missing required key 'sheets'"),
  )
}

///|
test "load requires each sheet to have a name" {
  assert_eq(
    schema_message("sheets:\n  - cells:\n      A1: x\n"),
    Some("spec.yaml: a sheet is missing required key 'name'"),
  )
}

///|
test "load rejects an invalid cell reference" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    cells:\n      A0: x\n"),
    Some("spec.yaml: 'A0' is not a valid A1 cell reference"),
  )
}

///|
test "load rejects a non-scalar cell value" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    cells:\n      A1: [1, 2]\n"),
    Some("spec.yaml: cell 'A1' must be text, a number, or a boolean"),
  )
}

///|
test "load rejects duplicate sheet names" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n  - name: S\n"),
    Some("spec.yaml: duplicate sheet name 'S'"),
  )
}

///|
test "a named style is declared once and referenced by name from many cells" {
  let workbook = load_ok(
    (
      #|defs:
      #|  styles:
      #|    header: { font: { bold: true }, fill: "DDDDDD" }
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: A
      #|        style: header
      #|    cells:
      #|      A1: { value: "Name", style: header }
      #|      B1: { value: "Qty", style: header }
      #|
    ),
  )
  let sheet = workbook.sheets[0]
  let header : @model.Style = {
    ..@model.Style::empty(),
    font: Some({
      bold: Some(true),
      italic: None,
      underline: None,
      strike: None,
      size: None,
      name: None,
      color: None,
    }),
    fill: Some({ color: @units.Color::parse("DDDDDD").unwrap() }),
  }
  // Both cells and the column band resolve to the one declared style, so the
  // emitter interns them to a single cellXfs id (ADR-004).
  assert_eq(sheet.cells[0].style, Some(header))
  assert_eq(sheet.cells[1].style, Some(header))
  assert_eq(sheet.columns[0].style, Some(header))
}

///|
test "a style reference still layers a cell's own format on top" {
  let workbook = load_ok(
    (
      #|defs:
      #|  styles:
      #|    money: { font: { bold: true } }
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: 1.5, style: money, format: "0.00" }
      #|
    ),
  )
  let style = workbook.sheets[0].cells[0].style.unwrap()
  assert_eq(style.font.unwrap().bold, Some(true))
  assert_eq(style.number_format, Some("0.00"))
}

///|
test "named values and formulas become defined names, referenced as =name" {
  let workbook = load_ok(
    (
      #|defs:
      #|  values:
      #|    company: "Acme Corp"
      #|    tax_rate: 0.08
      #|  formulas:
      #|    subtotal: "=SUM(B2:B9)"
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { $ref: company }
      #|      A2: { value: { $ref: tax_rate }, format: "0.00%" }
      #|      B10: { formula: { $ref: subtotal }, value: 100 }
      #|
    ),
  )
  // Each reference compiles to `=name`, caching the value it stands for (ADR-013).
  let cells = workbook.sheets[0].cells
  assert_eq(
    cells[0].value,
    @model.Formula(formula="company", cached=Some(@model.Text("Acme Corp"))),
  )
  assert_eq(
    cells[1].value,
    @model.Formula(formula="tax_rate", cached=Some(@model.Number(0.08))),
  )
  assert_eq(cells[1].style, Some(@model.Style::number_format("0.00%")))
  // A formula reference caches the cell's own `value`.
  assert_eq(
    cells[2].value,
    @model.Formula(formula="subtotal", cached=Some(@model.Number(100.0))),
  )
  // Every declared value/formula is registered as a defined name, in order.
  assert_eq(workbook.defined_names, [
    { name: "company", refers_to: @model.Text("Acme Corp") },
    { name: "tax_rate", refers_to: @model.Number(0.08) },
    {
      name: "subtotal",
      refers_to: @model.Formula(formula="SUM(B2:B9)", cached=None),
    },
  ])
}

///|
test "load rejects references to undefined names" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: ghost }\n",
    ),
    Some("spec.yaml: cell 'A1' references undefined style 'ghost'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { $ref: missing }\n",
    ),
    Some("spec.yaml: cell 'A1' references undefined value 'missing'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { formula: { $ref: nope } }\n",
    ),
    Some("spec.yaml: cell 'A1' references undefined formula 'nope'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: A\n        style: gone\n",
    ),
    Some("spec.yaml: column 'A' references undefined style 'gone'"),
  )
}

///|
test "load rejects a $ref value combined with a type, and unknown defs keys" {
  assert_eq(
    schema_message(
      "defs:\n  values:\n    n: 1\nsheets:\n  - name: S\n    cells:\n      A1: { value: { $ref: n }, type: text }\n",
    ),
    Some("spec.yaml: cell 'A1' cannot combine a '$ref' value with 'type'"),
  )
  assert_eq(
    schema_message("defs:\n  colors: {}\nsheets:\n  - name: S\n"),
    Some(
      "spec.yaml: unknown key 'colors' in 'defs' (expected 'styles', 'values', or 'formulas')",
    ),
  )
}

///|
test "load parses sheet visibility and the active sheet, keeping declaration order" {
  let workbook = load_ok(
    (
      #|active: Summary
      #|sheets:
      #|  - name: Data
      #|  - name: Summary
      #|  - name: Scratch
      #|    visibility: hidden
      #|  - name: Internals
      #|    visibility: very_hidden
      #|
    ),
  )
  // Sheet order is declaration order — the spec is the tab order.
  assert_eq(workbook.sheets.map(sheet => sheet.name), [
    "Data", "Summary", "Scratch", "Internals",
  ])
  assert_eq(workbook.sheets.map(sheet => sheet.visibility), [
    Visible,
    Visible,
    Hidden,
    VeryHidden,
  ])
  assert_eq(workbook.active_sheet, Some("Summary"))
  // Left out, `active` opens on the first sheet and every tab is visible.
  let plain = load_ok("sheets:\n  - name: S\n")
  assert_eq(plain.active_sheet, None)
  assert_eq(plain.sheets[0].visibility, Visible)
}

///|
test "load rejects a bad visibility, a dangling or hidden active sheet, and an all-hidden workbook" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    visibility: gone\n"),
    Some(
      "spec.yaml: unknown sheet visibility 'gone' (expected 'visible', 'hidden', or 'very_hidden')",
    ),
  )
  assert_eq(
    schema_message("active: Nope\nsheets:\n  - name: S\n"),
    Some("spec.yaml: active sheet 'Nope' is not a declared sheet"),
  )
  // Excel cannot open on a tab it does not show.
  assert_eq(
    schema_message(
      "active: S\nsheets:\n  - name: S\n    visibility: hidden\n  - name: T\n",
    ),
    Some("spec.yaml: active sheet 'S' is hidden"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    visibility: hidden\n  - name: T\n    visibility: very_hidden\n",
    ),
    Some(
      "spec.yaml: every sheet is hidden; Excel needs at least one visible sheet",
    ),
  )
}

///|
test "load parses frozen and split panes, gridlines, and a tab color" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: Report
      #|    freeze: B2
      #|    gridlines: false
      #|    tab_color: "1F77B4"
      #|  - name: Wide
      #|    split: { x: 120 }
      #|
    ),
  )
  let report = workbook.sheets[0]
  assert_eq(report.panes, Some(Freeze(@units.CellRef::new(col=2, row=2))))
  assert_eq(report.gridlines, Some(false))
  assert_eq(report.tab_color, @units.Color::parse("1F77B4"))
  // An axis left out of `split` stays unsplit.
  assert_eq(workbook.sheets[1].panes, Some(Split(x=120.0, y=0.0)))
  // Left out, all three keep Excel's defaults.
  let plain = load_ok("sheets:\n  - name: S\n")
  assert_eq(plain.sheets[0].panes, None)
  assert_eq(plain.sheets[0].gridlines, None)
  assert_eq(plain.sheets[0].tab_color, None)
}

///|
test "load rejects a pointless or malformed freeze, split, and tab color" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    freeze: A1\n"),
    Some(
      "spec.yaml: 'freeze: A1' would freeze nothing (freeze at the first unfrozen cell)",
    ),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    freeze: B\n"),
    Some("spec.yaml: 'B' is not a valid A1 cell reference in 'freeze'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    split: { x: 0, y: 0 }\n"),
    Some("spec.yaml: sheet 'split' needs a non-zero 'x' or 'y' (in points)"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    split: { z: 1 }\n"),
    Some("spec.yaml: unknown key 'z' in sheet 'split' (expected 'x' or 'y')"),
  )
  // Excel's viewport is either frozen or split, not both.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    freeze: B2\n    split: { x: 1 }\n",
    ),
    Some("spec.yaml: sheet 'S' cannot combine 'freeze' and 'split'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    tab_color: nope\n"),
    Some("spec.yaml: sheet 'tab_color' is not a valid hex color: 'nope'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    gridlines: sometimes\n"),
    Some("spec.yaml: sheet 'gridlines' must be true or false"),
  )
}

///|
test "load parses a print block: area, orientation, margins, fit, header/footer, breaks" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: Report
      #|    print:
      #|      area: A1:D50
      #|      orientation: landscape
      #|      margins: { top: 1, bottom: 1, left: 0.7, right: 0.7 }
      #|      fit: { width: 1 }
      #|      header: "&CQuarterly report"
      #|      footer: "&LPage &P of &N"
      #|      breaks: [A21, C1]
      #|
    ),
  )
  let page = workbook.sheets[0].page.unwrap()
  assert_eq(
    page.area,
    Some({
      top_left: @units.CellRef::new(col=1, row=1),
      bottom_right: @units.CellRef::new(col=4, row=50),
    }),
  )
  assert_eq(page.orientation, Some(Landscape))
  assert_eq(
    page.margins,
    Some({
      top: Some(1.0),
      bottom: Some(1.0),
      left: Some(0.7),
      right: Some(0.7),
      header: None,
      footer: None,
    }),
  )
  // An axis left out of `fit` is unconstrained.
  assert_eq(page.scale, Some(Fit(width=1, height=0)))
  assert_eq(page.header, Some("&CQuarterly report"))
  assert_eq(page.footer, Some("&LPage &P of &N"))
  assert_eq(page.breaks, [
    @units.CellRef::new(col=1, row=21),
    @units.CellRef::new(col=3, row=1),
  ])
  // A percentage scale is the other half of Excel's scaling control.
  let scaled = load_ok("sheets:\n  - name: S\n    print: { scale: 80 }\n")
  assert_eq(scaled.sheets[0].page.unwrap().scale, Some(Percent(80)))
  // No `print:` block leaves Excel's defaults throughout.
  assert_eq(load_ok("sheets:\n  - name: S\n").sheets[0].page, None)
}

///|
test "load rejects out-of-range, contradictory, and malformed print settings" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { scale: 5 }\n"),
    Some("spec.yaml: print 'scale' must be between 10 and 400 percent"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { scale: 80.5 }\n"),
    Some("spec.yaml: print 'scale' must be a whole number of percent"),
  )
  // Excel scales by a percentage or by a page fit, never both.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    print: { scale: 80, fit: { width: 1 } }\n",
    ),
    Some(
      "spec.yaml: sheet 'print' cannot combine 'scale' and 'fit' (Excel scales by one or the other)",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    print: { fit: { width: 0, height: 0 } }\n",
    ),
    Some(
      "spec.yaml: print 'fit' needs a non-zero 'width' or 'height' (in pages)",
    ),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { fit: { width: -1 } }\n"),
    Some(
      "spec.yaml: print 'fit' width must be a whole number of pages (0 for unconstrained)",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    print: { orientation: sideways }\n",
    ),
    Some(
      "spec.yaml: unknown print orientation 'sideways' (expected 'portrait' or 'landscape')",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    print: { margins: { top: -1 } }\n",
    ),
    Some("spec.yaml: print margin 'top' cannot be negative"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { area: A1 }\n"),
    Some("spec.yaml: print area 'A1' must be 'TopLeft:BottomRight'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { breaks: [A1] }\n"),
    Some("spec.yaml: a print break at 'A1' would break nothing"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { paper: a4 }\n"),
    Some(
      "spec.yaml: unknown key 'paper' in sheet 'print' (expected 'area', 'orientation', 'margins', 'scale', 'fit', 'header', 'footer', or 'breaks')",
    ),
  )
}

///|
test "an include stands wherever a node may, and nests" {
  let workbook = load_ok(
    (
      #|defs:
      #|  styles:
      #|    $include: theme.yaml
      #|sheets:
      #|  - name: Sales
      #|    columns:
      #|      $include: layout.yaml
      #|    cells:
      #|      $include: data.yaml
      #|
    ),
    files={
      // A `defs.styles` map, itself pulling one style from a third file.
      "theme.yaml": "header: { font: { bold: true } }\ntotal:\n  $include: total-style.yaml\n",
      "total-style.yaml": "font: { italic: true }\n",
      "layout.yaml": "- at: B\n  width: 14\n",
      "data.yaml": "A1: { value: Region, style: header }\nB1: 42\n",
    },
  )
  let sheet = workbook.sheets[0]
  // The included cells, columns, and styles all landed in the one model.
  assert_eq(sheet.cells[0].value, @model.Text("Region"))
  assert_eq(sheet.cells[0].style.unwrap().font.unwrap().bold, Some(true))
  assert_eq(sheet.cells[1].value, @model.Number(42.0))
  assert_eq(sheet.columns[0].size, Some(14.0))
  // The nested include resolved too: `total` came from a file inside a file.
  assert_eq(sheet.cells.length(), 2)
  let nested = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { value: x, style: total }\ndefs:\n  styles:\n    $include: theme.yaml\n",
    files={
      "theme.yaml": "total:\n  $include: total-style.yaml\n",
      "total-style.yaml": "font: { italic: true }\n",
    },
  )
  assert_eq(
    nested.sheets[0].cells[0].style.unwrap().font.unwrap().italic,
    Some(true),
  )
}

///|
test "a whole sheet, and a whole document, can be an include" {
  let workbook = load_ok("$include: workbook.yaml\n", files={
    "workbook.yaml": "sheets:\n  - $include: sheet.yaml\n",
    "sheet.yaml": "name: FromFile\ncells:\n  A1: hello\n",
  })
  assert_eq(workbook.sheets.length(), 1)
  assert_eq(workbook.sheets[0].name, "FromFile")
  assert_eq(workbook.sheets[0].cells[0].value, @model.Text("hello"))
}

///|
test "load rejects include cycles, siblings, and a non-text path" {
  // The cycle names the whole chain, so the offending edge is findable.
  assert_eq(
    schema_message("$include: a.yaml\n", files={
      "a.yaml": "$include: b.yaml\n",
      "b.yaml": "$include: a.yaml\n",
    }),
    Some("b.yaml: include cycle: spec.yaml -> a.yaml -> b.yaml -> a.yaml"),
  )
  // A file including itself is the shortest cycle.
  assert_eq(
    schema_message("$include: self.yaml\n", files={
      "self.yaml": "$include: self.yaml\n",
    }),
    Some("self.yaml: include cycle: spec.yaml -> self.yaml -> self.yaml"),
  )
  // An include replaces its whole node, so siblings would be dropped.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      $include: data.yaml\n      A1: kept?\n",
      files={ "data.yaml": "B1: 1\n" },
    ),
    Some(
      "spec.yaml: '$include' cannot be combined with other keys (it replaces the whole node)",
    ),
  )
  assert_eq(
    schema_message("sheets:\n  $include: 42\n"),
    Some("spec.yaml: '$include' must be text"),
  )
}

///|
test "a diagnostic in an included file names that file, not the including one" {
  // The schema error is in data.yaml, and the message says so.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      $include: data.yaml\n",
      files={ "data.yaml": "ZZ: 1\n" },
    ),
    Some("spec.yaml: 'ZZ' is not a valid A1 cell reference"),
  )
  // A *syntax* error in an included file is reported against that file.
  assert_eq(
    schema_message("sheets:\n  $include: broken.yaml\n", files={
      "broken.yaml": "- [unclosed\n",
    }),
    // The parser library's error renders as a bare type name today; carrying its
    // line/col through is Phase 8's rich-diagnostics work.
    Some(
      "broken.yaml: invalid YAML: moonbit-community/yaml.YamlError.YamlError",
    ),
  )
}

///|
test "a spec that includes without a resolver fails rather than guessing" {
  let document = @yaml.parse(
    "sheets:\n  $include: data.yaml\n",
    file="spec.yaml",
  )
  let message = try {
    @loader.load(document, file="spec.yaml") |> ignore
    None
  } catch {
    @diag.SchemaError(d) => Some(d.render())
    other => Some(other.to_string())
  }
  assert_eq(
    message,
    Some(
      "spec.yaml: cannot resolve '$include: data.yaml' — this caller provides no way to read files",
    ),
  )
}

///|
test "load rejects an unknown key inside a sheet" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    color: red\n"),
    Some(
      "spec.yaml: unknown key 'color' in sheet (expected 'name', 'cells', 'columns', 'rows', 'merges', 'visibility', 'freeze', 'split', 'gridlines', 'tab_color', or 'print')",
    ),
  )
}
