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
      #|        { pos: { col: 1, row: 1 }, value: Text("hello") },
      #|        { pos: { col: 2, row: 1 }, value: Number(42) },
      #|        { pos: { col: 3, row: 1 }, value: Bool(true) },
      #|        { pos: { col: 4, row: 1 }, value: Number(3.5) },
      #|      ],
      #|    },
      #|    {
      #|      name: "Second",
      #|      cells: [{ pos: { col: 1, row: 1 }, value: Text("42") }],
      #|    },
      #|  ],
      #|}
    ),
  )
}

///|
test "load rejects an unknown top-level key" {
  assert_eq(
    schema_message("sheetz:\n  - name: S\n"),
    Some("spec.yaml: unknown top-level key 'sheetz' (expected 'sheets')"),
  )
}

///|
test "load requires the sheets key" {
  assert_eq(
    schema_message("title: report\n"),
    Some("spec.yaml: unknown top-level key 'title' (expected 'sheets')"),
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
