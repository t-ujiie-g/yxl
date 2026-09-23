///|
/// `body` as a sheet's `layouts:` entries, with a style the tests can name.
fn layout_spec(body : String) -> String {
  (
    #|defs:
    #|  styles:
    #|    head: { font: { bold: true } }
    #|    weak: { font: { color: "C00000" } }
    #|sheets:
    #|  - name: 実績
    #|    layouts:
    #|
  ) +
  body
}

///|
test "a layout loads to exactly what the hand-written spec loads to" {
  let layout = load_ok(
    layout_spec(
      (
        #|      - at: B2
        #|        rows: 3
        #|        header_style: head
        #|        columns:
        #|          - { name: item, header: 項目, width: 18 }
        #|          - { name: cy, header: 当年, format: "#,##0" }
        #|          - { name: py, header: 前年, format: "#,##0" }
        #|          - name: ratio
        #|            header: 前年比
        #|            format: "0.0%"
        #|            formula: 'IFERROR({{cy}}/{{py}}-1,"")'
        #|            conditional:
        #|              - { cell: { less_than: 0 }, style: weak }
        #|              - { formula: "{{ratio}}>{{cy}}", style: head }
      ),
    ),
  )
  let by_hand = load_ok(
    (
      #|defs:
      #|  styles:
      #|    head: { font: { bold: true } }
      #|    weak: { font: { color: "C00000" } }
      #|sheets:
      #|  - name: 実績
      #|    columns:
      #|      - { at: B, width: 18 }
      #|      - { at: C, format: "#,##0" }
      #|      - { at: D, format: "#,##0" }
      #|      - { at: E, format: "0.0%" }
      #|    cells:
      #|      B2: { value: 項目, style: head }
      #|      C2: { value: 当年, style: head }
      #|      D2: { value: 前年, style: head }
      #|      E2: { value: 前年比, style: head }
      #|    formulas:
      #|      - { at: E3:E5, formula: 'IFERROR(C3/D3-1,"")' }
      #|    conditional:
      #|      - { at: E3:E5, cell: { less_than: 0 }, style: weak }
      #|      - { at: E3:E5, formula: "E3>C3", style: head }
    ),
  )
  assert_eq(layout, by_hand)
}

///|
test "without a header the body starts at the anchor" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 2\n        columns:\n          - { name: a }\n          - { name: b, formula: \"{{a}}*2\" }\n",
      ),
    ).sheets[0]
  assert_eq(sheet.cells.length(), 0)
  assert_eq(sheet.columns.length(), 0)
  assert_eq(sheet.formulas[0].at.to_a1(), "B1:B2")
  assert_eq(sheet.formulas[0].formula, "A1*2")
}

///|
test "'{{' inside a formula's string literal is text" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a }\n          - { name: b, formula: '{{a}}&\"{{a}}\"\"{{a}}\"' }\n",
      ),
    ).sheets[0]
  assert_eq(sheet.formulas[0].formula, "A1&\"{{a}}\"\"{{a}}\"")
}

///|
test "two layouts on one sheet place independently" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, width: 9 }]\n      - at: C5\n        rows: 1\n        columns: [{ name: b, header: B }]\n",
      ),
    ).sheets[0]
  assert_eq(sheet.columns[0].first, 1)
  assert_eq(sheet.cells[0].pos.to_a1(), "C5")
}

///|
test "a layout's own keys are required and checked" {
  assert_eq(
    schema_message(
      layout_spec("      - rows: 1\n        columns: [{ name: a }]\n"),
    ),
    Some("spec.yaml: a layout is missing required key 'at'"),
  )
  assert_eq(
    schema_message(
      layout_spec("      - at: A1\n        columns: [{ name: a }]\n"),
    ),
    Some(
      "spec.yaml: layout 'A1' needs 'rows', or a 'values', 'csv', or 'json' to count them from",
    ),
  )
  assert_eq(
    schema_message(layout_spec("      - at: A1\n        rows: 1\n")),
    Some("spec.yaml: layout 'A1' is missing required key 'columns'"),
  )
  assert_eq(
    schema_message(
      layout_spec("      - at: A1\n        rows: 1\n        columns: []\n"),
    ),
    Some("spec.yaml: layout 'A1' has no columns"),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        body: 3-9\n        columns: [{ name: a }]\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'body' in layout 'A1' (expected 'at', 'rows', 'header_style', 'columns', 'values', 'csv', 'json', or 'footer')",
    ),
  )
}

///|
test "'rows' is a whole number inside Excel's grid" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 0\n        columns: [{ name: a }]\n",
      ),
    ),
    Some("spec.yaml: layout 'A1' 'rows' must be a whole number of at least 1"),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A2\n        rows: 1048576\n        columns: [{ name: a }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A2' body ends at row 1048577, past Excel's last row (1048576)",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: XFD1\n        rows: 1\n        columns: [{ name: a }, { name: b }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'XFD1' has 2 columns, which run past Excel's last column (XFD)",
    ),
  )
}

///|
test "a column needs a name that '{{name}}' can spell, once per sheet" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ width: 9 }]\n",
      ),
    ),
    Some("spec.yaml: a column of layout 'A1' is missing required key 'name'"),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: sales.cy }]\n",
      ),
    ),
    Some(
      "spec.yaml: column name 'sales.cy' in layout 'A1' must be letters, digits and '_', not starting with a digit",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: 1st }]\n",
      ),
    ),
    Some(
      "spec.yaml: column name '1st' in layout 'A1' must be letters, digits and '_', not starting with a digit",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a }]\n      - at: C1\n        rows: 1\n        columns: [{ name: a }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'C1' column 'a' reuses a name layout 'A1' already has on sheet '実績'",
    ),
  )
}

///|
test "a column's unknown key lists both its own keys and its band's" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, at: C }]\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'at' in layout 'A1' column 'a' (expected 'name', 'header', 'field', 'formula', 'conditional', 'width', 'style', 'format', 'hidden', or 'group')",
    ),
  )
}

///|
test "a formula naming no column of its layout is refused" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a }\n          - { name: b, formula: \"{{c}}+1\" }\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' column 'b' formula refers to '{{c}}', which is not a column of this layout ('a' or 'b')",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a }\n          - { name: b, formula: \"{{a+1\" }\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' column 'b' formula has a '{{' with no closing '}}'",
    ),
  )
}

///|
test "a column formula keeps the filled-range rules" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a, formula: { $ref: f } }\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' column 'a' 'formula' cannot be a '$ref': a named formula compiles to a defined name, so every cell would hold the same formula rather than one that shifts per row — write the formula here instead",
    ),
  )
}

///|
test "a column's conditional covers its body and takes no 'at'" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - name: a\n            conditional: [{ at: A1:A9, duplicate: true, style: weak }]\n",
      ),
    ),
    Some(
      "spec.yaml: a conditional format of layout 'A1' column 'a' takes no 'at'; it covers the column's body",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - name: a\n            conditional: [{ duplicate: true }]\n",
      ),
    ),
    Some(
      "spec.yaml: conditional of layout 'A1' column 'a' needs a 'style' (or a 'format') to apply where it matches",
    ),
  )
}

///|
test "a header style needs a header, and two layouts may not band one column" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_style: head\n        columns: [{ name: a }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' has a 'header_style' but no column has a 'header' to wear it",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, width: 9 }]\n      - at: A5\n        rows: 1\n        columns: [{ name: b, width: 12 }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A5' column 'b' lands on a column layout 'A1' column 'a' already formats; give the column its width and style in one layout",
    ),
  )
}

///|
test "a layout formula column still refuses a cell written over it" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 3\n        columns:\n          - { name: a }\n          - { name: b, formula: \"{{a}}*2\" }\n    cells:\n      B2: 5\n",
      ),
    ),
    Some(
      "spec.yaml: formula range 'B1:B3' on sheet '実績' covers 'B2', which the sheet also writes as a cell; split the range around it rather than letting one silently win",
    ),
  )
}

///|
/// What a sheet writes at each address: its value and whether it wears a style.
fn written(sheet : @model.Sheet) -> Map[String, (@model.CellValue, Bool)] {
  let cells = Map([])
  for cell in sheet.cells {
    cells[cell.pos.to_a1()] = (cell.value, cell.style is Some(_))
  }
  cells
}

///|
fn merged(sheet : @model.Sheet) -> Array[String] {
  sheet.merges.map(range => range.to_a1())
}
