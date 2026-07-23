///|
/// Parse then load, returning the schema-error message if loading fails.
fn schema_message(source : String) -> String? raise {
  let document = @yaml.parse(source, file="spec.yaml")
  try {
    @loader.load(document, file="spec.yaml") |> ignore
    None
  } catch {
    @diag.SchemaError(d) => Some(d.render())
  }
}

///|
/// Parse then load a spec expected to be valid.
fn load_ok(source : String) -> @model.Workbook raise {
  @loader.load(@yaml.parse(source, file="spec.yaml"), file="spec.yaml")
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
      #|      column_styles: [],
      #|      row_styles: [],
      #|    },
      #|    {
      #|      name: "Second",
      #|      cells: [{ pos: { col: 1, row: 1 }, value: Text("42"), style: None }],
      #|      column_styles: [],
      #|      row_styles: [],
      #|    },
      #|  ],
      #|  date_system: Date1900,
      #|  default_font: None,
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
  assert_eq(sheet.column_styles.length(), 2)
  assert_eq(sheet.column_styles[0].first, 2)
  assert_eq(sheet.column_styles[0].last, 2)
  assert_eq(sheet.column_styles[0].style.font.unwrap().bold, Some(true))
  assert_eq(sheet.column_styles[1].first, 4)
  assert_eq(sheet.column_styles[1].last, 6)
  assert_eq(sheet.column_styles[1].style.number_format, Some("0.00"))
  // Row 1 filled; rows 2-3 right-aligned as one band.
  assert_eq(sheet.row_styles.length(), 2)
  assert_eq((sheet.row_styles[0].first, sheet.row_styles[0].last), (1, 1))
  assert_eq((sheet.row_styles[1].first, sheet.row_styles[1].last), (2, 3))
  assert_eq(sheet.row_styles[1].style.align.unwrap().horizontal, Some(Right))
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
  // An empty band spec adds no style rather than erroring.
  let workbook = load_ok("sheets:\n  - name: S\n    columns:\n      - at: B\n")
  assert_eq(workbook.sheets[0].column_styles.length(), 0)
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
      "spec.yaml: unknown top-level key 'sheetz' (expected 'sheets', 'date1904', or 'default_font')",
    ),
  )
}

///|
test "load requires the sheets key" {
  assert_eq(
    schema_message("title: report\n"),
    Some(
      "spec.yaml: unknown top-level key 'title' (expected 'sheets', 'date1904', or 'default_font')",
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
test "load rejects an unknown key inside a sheet" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    color: red\n"),
    Some(
      "spec.yaml: unknown key 'color' in sheet (expected 'name', 'cells', 'columns', or 'rows')",
    ),
  )
}
