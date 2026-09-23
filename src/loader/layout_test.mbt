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

///|
test "header levels merge a shared parent across and a short column down" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: A2
          #|        rows: 2
          #|        header_style: head
          #|        columns:
          #|          - { name: item, header: 部門 }
          #|          - { name: cy, header: [売上, 当年] }
          #|          - { name: py, header: [売上, 前年] }
          #|          - { name: ratio, header: [売上, 前年比], formula: "{{cy}}/{{py}}" }
        ),
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A2:A3", "B2:D2"])
  let cells = written(sheet)
  assert_eq(cells.get("A2"), Some((Text("部門"), true)))
  assert_eq(cells.get("A3"), Some((Blank, true)))
  assert_eq(cells.get("B2"), Some((Text("売上"), true)))
  assert_eq(cells.get("C2"), Some((Blank, true)))
  assert_eq(cells.get("D2"), Some((Blank, true)))
  assert_eq(cells.get("D3"), Some((Text("前年比"), true)))
  assert_eq(sheet.formulas[0].at.to_a1(), "D4:D5")
  assert_eq(sheet.formulas[0].formula, "B4/C4")
}

///|
test "a null level is a blank that merges with nothing" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: A1
          #|        rows: 1
          #|        header_style: head
          #|        columns:
          #|          - { name: item, header: [null, 部門] }
          #|          - { name: cy, header: [売上, 当年] }
          #|          - { name: py, header: [null, 前年] }
        ),
      ),
    ).sheets[0]
  assert_eq(merged(sheet), [])
  let cells = written(sheet)
  assert_eq(cells.get("A1"), Some((Blank, true)))
  assert_eq(cells.get("A2"), Some((Text("部門"), true)))
  assert_eq(cells.get("C1"), Some((Blank, true)))
  assert_eq(cells.get("C2"), Some((Text("前年"), true)))
}

///|
test "without a header style a blank writes no cell at all" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a, header: [X, a] }\n          - { name: b, header: [X, b] }\n          - { name: c, header: [null, c] }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A1:B1"])
  let cells = written(sheet)
  assert_eq(cells.get("B1"), None)
  assert_eq(cells.get("C1"), None)
  assert_eq(cells.get("A1"), Some((Text("X"), false)))
}

///|
test "the same label under different parents stays apart" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a, header: [売上, 当年] }\n          - { name: b, header: [粗利, 当年] }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), [])
}

///|
test "a level stretched down never also merges across" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a, header: 備考 }\n          - { name: b, header: 備考 }\n          - { name: c, header: [X, c] }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A1:A2", "B1:B2"])
}

///|
test "a header cell's own style is laid over the header style" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_style: head\n        columns:\n          - { name: a, header: { value: A, style: weak } }\n",
      ),
    ).sheets[0]
  guard sheet.cells[0].style is Some(style) else { fail("unstyled header") }
  guard style.font is Some(font) else { fail("no font") }
  assert_eq(font.bold, Some(true))
  assert_true(font.color is Some(_))
}

///|
test "a header's levels are cells, and there is at least one" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, header: [] }]\n",
      ),
    ),
    Some("spec.yaml: layout 'A1' column 'a' header is an empty list"),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, header: [[x]] }]\n",
      ),
    ),
    Some("spec.yaml: layout 'A1' column 'a' header levels are cells, not lists"),
  )
}

///|
/// A report whose `ratio` column is derived, fed rows by `source`.
fn fed_layout(source : String) -> String {
  layout_spec(
    (
      #|      - at: A1
      #|        columns:
      #|          - { name: item, header: 部門 }
      #|          - { name: cy, header: 当年 }
      #|          - { name: ratio, header: 比, formula: "{{cy}}/{{py}}" }
      #|          - { name: py, header: 前年 }
      #|
    ) +
    source,
  )
}

///|
test "inline rows fill only the columns without a formula, and count the body" {
  let sheet = load_ok(
      fed_layout(
        "        values:\n          - [東日本, 520, 480]\n          - [九州, 190]\n",
      ),
    ).sheets[0]
  let cells = written(sheet)
  assert_eq(cells.get("A2"), Some((Text("東日本"), false)))
  assert_eq(cells.get("B2"), Some((Number(520.0), false)))
  assert_eq(cells.get("C2"), None)
  assert_eq(cells.get("D2"), Some((Number(480.0), false)))
  assert_eq(cells.get("D3"), None)
  assert_eq(sheet.formulas[0].at.to_a1(), "C2:C3")
}

///|
test "'rows' may reserve more body than the data fills, never less" {
  let sheet = load_ok(
      fed_layout("        rows: 5\n        values: [[東日本, 520, 480]]\n"),
    ).sheets[0]
  assert_eq(sheet.formulas[0].at.to_a1(), "C2:C6")
  assert_eq(
    schema_message(
      fed_layout("        rows: 1\n        values: [[a, 1, 2], [b, 3, 4]]\n"),
    ),
    Some(
      "spec.yaml: layout 'A1' 'rows' is 1, fewer than the 2 rows its data holds",
    ),
  )
  assert_eq(
    schema_message(fed_layout("        values: []\n")),
    Some(
      "spec.yaml: layout 'A1' reads no rows from its data, and sets no 'rows' to reserve",
    ),
  )
}

///|
test "a positional row longer than the input columns is refused" {
  assert_eq(
    schema_message(fed_layout("        values: [[a, 1, 2, 3]]\n")),
    Some(
      "spec.yaml: row 1 of layout 'A1' has 4 fields, but the layout has 3 columns without a formula to take them",
    ),
  )
}

///|
test "a CSV is matched by its header row, in any order and with extra fields" {
  let sheet = load_ok(fed_layout("        csv: sales.csv\n"), files={
      "sales.csv": "py,note,item,cy\n480,x,東日本,520\n430,,西日本,410\n",
    }).sheets[0]
  let cells = written(sheet)
  assert_eq(cells.get("A3"), Some((Text("西日本"), false)))
  assert_eq(cells.get("B2"), Some((Number(520.0), false)))
  assert_eq(cells.get("D3"), Some((Number(430.0), false)))
  assert_eq(sheet.formulas[0].at.to_a1(), "C2:C3")
}

///|
test "'field' names the source field when it differs from the column's name" {
  let source =
    #|sheets:
    #|  - name: S
    #|    layouts:
    #|      - at: A1
    #|        csv: sales.csv
    #|        columns:
    #|          - { name: item, field: 部門名 }
    #|          - { name: cy, field: 売上金額 }
    #|
  let sheet = load_ok(source, files={
      "sales.csv": "部門名,売上金額\n東日本,520\n",
    }).sheets[0]
  assert_eq(written(sheet).get("B1"), Some((Number(520.0), false)))
  assert_eq(
    schema_message(source, files={
      "sales.csv": "部門,売上金額\n東日本,520\n",
    }),
    Some(
      "sales.csv: the header row has no field '部門名' for layout 'A1' column 'item' (fields: '部門' or '売上金額')",
    ),
  )
}

///|
test "JSON objects are matched by key, and JSON arrays by position" {
  let objects = load_ok(fed_layout("        json: sales.json\n"), files={
      "sales.json": "[{\"py\": 480, \"item\": \"東日本\", \"cy\": 520}]",
    }).sheets[0]
  assert_eq(written(objects).get("D2"), Some((Number(480.0), false)))
  let arrays = load_ok(fed_layout("        json: sales.json\n"), files={
      "sales.json": "[[\"東日本\", 520, 480]]",
    }).sheets[0]
  assert_eq(written(arrays).get("D2"), Some((Number(480.0), false)))
}

///|
test "'field' is refused where nothing reads it" {
  let spec = layout_spec(
    "      - at: A1\n        rows: 1\n        columns: [{ name: a, field: x }]\n",
  )
  assert_eq(
    schema_message(spec),
    Some(
      "spec.yaml: layout 'A1' column 'a' has a 'field' but the layout reads no 'csv' or 'json'",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        values: [[1]]\n        columns: [{ name: a, field: x }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' column 'a' has a 'field', but 'values' rows are matched by position",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, field: x, formula: \"1\" }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' column 'a' has both a 'field' and a 'formula'; a formula column takes no data",
    ),
  )
}

///|
test "a layout takes one source of rows, and a CSV needs its header row" {
  assert_eq(
    schema_message(
      fed_layout("        values: [[a, 1, 2]]\n        csv: sales.csv\n"),
    ),
    Some(
      "spec.yaml: layout 'A1' sets more than one source of rows ('values', 'csv', or 'json')",
    ),
  )
  assert_eq(
    schema_message(fed_layout("        csv: sales.csv\n"), files={
      "sales.csv": "",
    }),
    Some(
      "sales.csv: a CSV read by a layout starts with a header row naming its fields, and this one is empty",
    ),
  )
}
