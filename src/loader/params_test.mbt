// Parameters and `${name}` substitution (`params.mbt`).

///|
test "parameters substitute into values, keys, and sheet names" {
  let workbook = load_ok(
    (
      #|params:
      #|  region: APAC
      #|  row: 3
      #|  rate: 0.08
      #|sheets:
      #|  - name: "${region} sales"
      #|    cells:
      #|      A1: "Report for ${region}"
      #|      A${row}: filled by a parameterized key
      #|      B1: "${rate}"
      #|
    ),
  )
  let sheet = workbook.sheets[0]
  assert_eq(sheet.name, "APAC sales")
  assert_eq(sheet.cells[0].value, @model.Text("Report for APAC"))
  // A parameter in a mapping key works too, and renders as text.
  assert_eq(sheet.cells[1].pos, @units.CellRef::new(col=1, row=3))
  // A string that is *exactly* one placeholder keeps the parameter's type, so
  // this is a number cell rather than the text "0.08".
  assert_eq(sheet.cells[2].value, @model.Number(0.08))
}

///|
test "a parameter default may use another, and an override replaces it" {
  let source =
    #|params:
    #|  quarter: Q3
    #|  year: FY26
    #|  title: "${quarter} ${year} results"
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: "${title}"
    #|
  assert_eq(
    load_ok(source).sheets[0].cells[0].value,
    @model.Text("Q3 FY26 results"),
  )
  // An override reaches through the chain: `title` is rebuilt from it.
  assert_eq(
    load_ok(source, params={ "quarter": "Q4" }).sheets[0].cells[0].value,
    @model.Text("Q4 FY26 results"),
  )
  // A `--set` value is read as the scalar it looks like, so this stays a
  // number cell rather than becoming text.
  let typed = load_ok(
    "params:\n  rate: 0.08\nsheets:\n  - name: S\n    cells:\n      A1: \"${rate}\"\n",
    params={ "rate": "0.15" },
  )
  assert_eq(typed.sheets[0].cells[0].value, @model.Number(0.15))
}

///|
test "a '$' that begins no placeholder is literal, and '$$' escapes one" {
  let workbook = load_ok(
    (
      #|params:
      #|  n: 2
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { formula: "SUM($B$1:$B$10)" }
      #|      A2: "$${n} is written literally"
      #|      A3: { formula: "SUM($B$1:$B$$${n})" }
      #|
    ),
  )
  let cells = workbook.sheets[0].cells
  // Excel's absolute references survive untouched; only `${...}` substitutes.
  assert_eq(
    cells[0].value,
    @model.Formula(formula="SUM($B$1:$B$10)", cached=None),
  )
  assert_eq(cells[1].value, @model.Text("${n} is written literally"))
  // A literal `$` immediately before a placeholder is where the two meanings of
  // `$` collide: escape the `$`, then write the placeholder.
  assert_eq(
    cells[2].value,
    @model.Formula(formula="SUM($B$1:$B$2)", cached=None),
  )
}

///|
test "load rejects unknown, cyclic, and malformed parameters" {
  assert_eq(
    schema_message("sheets:\n  - name: \"${nope}\"\n"),
    Some("spec.yaml: undeclared parameter 'nope'"),
  )
  assert_eq(
    schema_message(
      "params:\n  a: \"${b}\"\n  b: \"${a}\"\nsheets:\n  - name: S\n",
    ),
    Some("spec.yaml: parameter cycle: a -> b -> a"),
  )
  assert_eq(
    schema_message("params:\n  a: \"${a}\"\nsheets:\n  - name: S\n"),
    Some("spec.yaml: parameter cycle: a -> a"),
  )
  assert_eq(
    schema_message("params:\n  a: 1\nsheets:\n  - name: \"${a\"\n"),
    Some("spec.yaml: a value has a '${' with no closing '}'"),
  )
  assert_eq(
    schema_message("params:\n  a: { x: 1 }\nsheets:\n  - name: S\n"),
    Some("spec.yaml: parameter 'a' must be text, a number, or a boolean"),
  )
  // A typo in `--set` says so rather than quietly doing nothing.
  assert_eq(
    schema_message("params:\n  region: APAC\nsheets:\n  - name: S\n", params={
      "regoin": "EMEA",
    }),
    Some("spec.yaml: cannot set 'regoin': the spec declares no such parameter"),
  )
}
