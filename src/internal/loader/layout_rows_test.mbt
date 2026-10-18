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

///|
/// The value and number format a loaded sheet holds at `reference`.
fn typed_cell(
  sheet : @model.Sheet,
  reference : String,
) -> (@model.CellValue, String?)? {
  for cell in sheet.cells {
    if cell.pos.to_a1() == reference {
      return Some((cell.value, cell.style.bind(style => style.number_format)))
    }
  }
  None
}

///|
test "a column's type reads a CSV field as written, so a code keeps its zeros" {
  let source =
    #|sheets:
    #|  - name: S
    #|    layouts:
    #|      - at: A1
    #|        csv: shops.csv
    #|        columns:
    #|          - { name: code, type: text }
    #|          - { name: opened, type: date }
    #|          - { name: seats, type: number }
    #|          - { name: open, type: bool }
    #|          - { name: hours, type: duration }
    #|          - { name: plain }
    #|
  let sheet = load_ok(source, files={
      "shops.csv": "code,opened,seats,open,hours,plain\n007,2026-04-01,\"12\",true,26:30,007\n,2026-04-01 09:30:00,,,,\n",
    }).sheets[0]
  assert_eq(typed_cell(sheet, "A1"), Some((Text("007"), None)))
  assert_eq(
    typed_cell(sheet, "B1"),
    Some(
      (Date(@units.DateTime::parse("2026-04-01").unwrap()), Some("yyyy-mm-dd")),
    ),
  )
  assert_eq(typed_cell(sheet, "C1"), Some((Number(12.0), None)))
  assert_eq(typed_cell(sheet, "D1"), Some((Bool(true), None)))
  assert_eq(
    typed_cell(sheet, "E1").map(cell => cell.1),
    Some(Some("[h]:mm:ss")),
  )
  assert_eq(typed_cell(sheet, "F1"), Some((Number(7.0), None)))
  assert_eq(typed_cell(sheet, "A2"), None)
  assert_eq(
    typed_cell(sheet, "B2").map(cell => cell.1),
    Some(Some("yyyy-mm-dd hh:mm:ss")),
  )
}

///|
test "a column's type reads inline rows too, and a set format wins over the default" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: A1
          #|        values: [[7, "2026-04-01", "2026-04-01", "2026-04-01"]]
          #|        columns:
          #|          - { name: code, type: text }
          #|          - { name: a, type: date }
          #|          - { name: b, type: date, format: "yyyy/m/d" }
          #|          - { name: c, type: date, body_style: { border: thin, format: "m月d日" } }
          #|
        ),
      ),
    ).sheets[0]
  assert_eq(typed_cell(sheet, "A1"), Some((Text("7"), None)))
  assert_eq(
    typed_cell(sheet, "B1").map(cell => cell.1),
    Some(Some("yyyy-mm-dd")),
  )
  assert_eq(typed_cell(sheet, "C1").map(cell => cell.1), Some(None))
  assert_eq(typed_cell(sheet, "D1").map(cell => cell.1), Some(Some("m月d日")))
}

///|
test "a field its column's type cannot read is refused with its row and column" {
  let typed = (column, row) => {
    schema_message(
      layout_spec(
        "      - at: A1\n        values: [[" +
        row +
        "]]\n        columns:\n          - " +
        column +
        "\n",
      ),
    )
  }
  assert_eq(
    typed("{ name: d, type: date }", "\"4月1日\""),
    Some(
      "spec.yaml: row 1 of layout 'A1' column 'd' is not a valid date: '4月1日'",
    ),
  )
  assert_eq(
    typed("{ name: n, type: number }", "\"12個\""),
    Some("spec.yaml: row 1 of layout 'A1' column 'n' is not a number: '12個'"),
  )
  assert_eq(
    typed("{ name: f, type: bool }", "1"),
    Some(
      "spec.yaml: row 1 of layout 'A1' column 'f' cannot be read as a boolean: '1'",
    ),
  )
  assert_eq(
    typed("{ name: h, type: duration }", "\"1h\""),
    Some(
      "spec.yaml: row 1 of layout 'A1' column 'h' is not a valid duration: '1h' (expected H:MM or H:MM:SS, hours unbounded)",
    ),
  )
  assert_eq(
    typed("{ name: e, type: error }", "x"),
    Some(
      "spec.yaml: unknown type 'error' for layout 'A1' column 'e' (expected 'text', 'number', 'bool', 'date', or 'duration')",
    ),
  )
  assert_eq(
    typed("{ name: t, type: text, formula: \"1\" }", "x"),
    Some(
      "spec.yaml: layout 'A1' column 't' has both a 'type' and a 'formula'; a formula column takes no data",
    ),
  )
}

///|
test "merge_equal merges equal runs down, cut where a column left of it changes" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: A1
          #|        values:
          #|          - [東京, 直営, 1]
          #|          - [東京, 直営, 2]
          #|          - [東京, FC, 3]
          #|          - [大阪, FC, 4]
          #|          - [大阪, null, 5]
          #|          - [大阪, null, 6]
          #|          - [福岡, 直営, 7]
          #|        columns:
          #|          - { name: branch, header: 支店, merge_equal: true }
          #|          - { name: channel, header: 区分, merge_equal: true }
          #|          - { name: amount, header: 金額 }
        ),
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A2:A4", "A5:A7", "B2:B3"])
  assert_eq(written(sheet).get("A3"), Some((Text("東京"), false)))
}

///|
test "merge_equal takes data, and no formula column" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 2\n        columns:\n          - { name: a, merge_equal: true }\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' column 'a' has 'merge_equal' but the layout reads no data to merge",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        values: [[1]]\n        columns:\n          - { name: a }\n          - { name: b, formula: \"{{a}}\", merge_equal: true }\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' column 'b' has both 'merge_equal' and a 'formula'; only data merges",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        values: [[1]]\n        columns:\n          - { name: a, merge_equal: 1 }\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' column 'a' 'merge_equal' must be true or false",
    ),
  )
}

///|
test "page_break_on starts a page wherever the column's value changes" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: A1
          #|        page_break_on: branch
          #|        values: [[東京, 1], [東京, 2], [大阪, 3], [福岡, 4]]
          #|        columns:
          #|          - { name: branch, header: 支店 }
          #|          - { name: amount, header: 金額 }
          #|
          #|    print: { breaks: [A20], orientation: landscape }
        ),
      ),
    ).sheets[0]
  guard sheet.page is Some(page) else { fail("no page setup") }
  assert_eq(page.breaks.map(at => at.to_a1()), ["A4", "A5", "A20"])
  assert_eq(page.orientation, Some(Landscape))
}

///|
test "page_break_on names a column the data fills" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        page_break_on: twice\n        values: [[1]]\n        columns:\n          - { name: a }\n          - { name: twice, formula: \"{{a}}*2\" }\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' 'page_break_on' names 'twice', which is not a column the layout's data fills",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        page_break_on: a\n        rows: 2\n        columns: [{ name: a }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' has 'page_break_on' but reads no data to break on",
    ),
  )
}
