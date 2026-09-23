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
