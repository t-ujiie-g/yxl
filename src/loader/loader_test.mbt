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
  assert_eq(cell.format, Some("yyyy-mm-dd"))
}

///|
test "a date-time value defaults to a date-time format, and format overrides" {
  let datetime = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { value: \"2026-07-23 14:30:00\", type: date }\n",
  )
  assert_eq(datetime.sheets[0].cells[0].format, Some("yyyy-mm-dd hh:mm:ss"))
  let custom = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { value: \"2026-07-23\", type: date, format: \"mmm d\" }\n",
  )
  assert_eq(custom.sheets[0].cells[0].format, Some("mmm d"))
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
      #|        { pos: { col: 1, row: 1 }, value: Text("hello"), format: None },
      #|        { pos: { col: 2, row: 1 }, value: Number(42), format: None },
      #|        { pos: { col: 3, row: 1 }, value: Bool(true), format: None },
      #|        { pos: { col: 4, row: 1 }, value: Number(3.5), format: None },
      #|      ],
      #|    },
      #|    {
      #|      name: "Second",
      #|      cells: [{ pos: { col: 1, row: 1 }, value: Text("42"), format: None }],
      #|    },
      #|  ],
      #|  date_system: Date1900,
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
  assert_eq(cells[0].format, Some("0.00%"))
  // A plain scalar cell keeps the General format.
  assert_eq(cells[1].value, @model.Number(42.0))
  assert_eq(cells[1].format, None)
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
      "spec.yaml: unknown key 'color' in cell 'A1' (expected 'value', 'formula', 'type', or 'format')",
    ),
  )
}

///|
test "load rejects an unknown top-level key" {
  assert_eq(
    schema_message("sheetz:\n  - name: S\n"),
    Some(
      "spec.yaml: unknown top-level key 'sheetz' (expected 'sheets' or 'date1904')",
    ),
  )
}

///|
test "load requires the sheets key" {
  assert_eq(
    schema_message("title: report\n"),
    Some(
      "spec.yaml: unknown top-level key 'title' (expected 'sheets' or 'date1904')",
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
    Some("spec.yaml: unknown key 'color' in sheet (expected 'name' or 'cells')"),
  )
}
