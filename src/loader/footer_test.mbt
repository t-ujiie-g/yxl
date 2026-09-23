///|
/// Stores by branch and channel, with a footer given by `footer`.
fn store_spec(footer : String) -> String {
  (
    #|defs:
    #|  styles:
    #|    sub: { font: { bold: true } }
    #|sheets:
    #|  - name: S
    #|    layouts:
    #|      - at: A1
    #|        values:
    #|          - [大阪, FC, 梅田, 30, 20]
    #|          - [東京, 直営, 銀座, 50, 40]
    #|          - [大阪, 直営, 難波, 70, 60]
    #|          - [東京, FC, 新宿, 10, 5]
    #|        columns:
    #|          - { name: branch, header: 支店 }
    #|          - { name: channel, header: 区分 }
    #|          - { name: store, header: 店舗 }
    #|          - { name: cy, header: 当年 }
    #|          - { name: py, header: 前年 }
    #|          - { name: ratio, header: 比, formula: "{{cy}}/{{py}}-1" }
    #|        footer:
    #|
  ) +
  footer
}

///|
/// What a footer wrote: each cell's value, by address.
fn footer_cells(footer : String) -> Map[String, @model.CellValue] raise {
  let cells = Map([])
  for cell in load_ok(store_spec(footer)).sheets[0].cells {
    if cell.pos.row > 5 {
      cells[cell.pos.to_a1()] = cell.value
    }
  }
  cells
}

///|
fn formula_at(cells : Map[String, @model.CellValue], at : String) -> String? {
  match cells.get(at) {
    Some(Formula(formula~, ..)) => Some(formula)
    _ => None
  }
}

///|
test "a grand total sums the column's body beneath it" {
  let cells = footer_cells(
    (
      #|          - row:
      #|              store: 合計
      #|              cy: { total: sum }
      #|              ratio: { formula: "{{cy}}/{{py}}-1" }
    ),
  )
  assert_eq(cells.get("C6"), Some(Text("合計")))
  assert_eq(formula_at(cells, "D6"), Some("SUM(D2:D5)"))
  assert_eq(formula_at(cells, "F6"), Some("D6/E6-1"))
}

///|
test "nested groups subtotal each branch, and each channel within it" {
  let cells = footer_cells(
    (
      #|          - by: branch
      #|            order: asc
      #|            rows:
      #|              - by: channel
      #|                order: [直営, FC]
      #|                rows:
      #|                  - row: { store: "{{branch}} {{channel}} 計", cy: { total: sum } }
      #|              - row: { store: "{{branch}} 計", cy: { total: sum } }
      #|                style: sub
      #|          - row: { store: 総合計, cy: { total: sum } }
    ),
  )
  let labels = (6).until(13).map(row => cells.get("C\{row}")).collect()
  assert_eq(labels, [
    Some(Text("大阪 直営 計")),
    Some(Text("大阪 FC 計")),
    Some(Text("大阪 計")),
    Some(Text("東京 直営 計")),
    Some(Text("東京 FC 計")),
    Some(Text("東京 計")),
    Some(Text("総合計")),
  ])
  assert_eq(
    formula_at(cells, "D6"),
    Some("SUMIFS(D2:D5,A2:A5,\"=大阪\",B2:B5,\"=直営\")"),
  )
  assert_eq(formula_at(cells, "D8"), Some("SUMIFS(D2:D5,A2:A5,\"=大阪\")"))
  assert_eq(formula_at(cells, "D12"), Some("SUM(D2:D5)"))
}

///|
test "a group's values come in data order, ascending, or descending" {
  let labels = (order : String) => {
    let cells = footer_cells(
      "          - by: branch\n            order: \{order}\n            rows: [{ row: { store: \"{{branch}}\" } }]\n",
    )
    [cells.get("C6"), cells.get("C7")]
  }
  assert_eq(labels("data"), [Some(Text("大阪")), Some(Text("東京"))])
  assert_eq(labels("desc"), [Some(Text("東京")), Some(Text("大阪"))])
}

///|
test "a listed order gives a row to every value, present or not" {
  let cells = footer_cells(
    "          - by: branch\n            order: [東京, 大阪, 福岡]\n            rows: [{ row: { store: \"{{branch}}\", cy: { total: count } } }]\n",
  )
  assert_eq(cells.get("C8"), Some(Text("福岡")))
  assert_eq(
    formula_at(cells, "D8"),
    Some("COUNTIFS(D2:D5,\"<>\",A2:A5,\"=福岡\")"),
  )
}

///|
test "a row's style reaches every column of the layout" {
  let sheet = load_ok(
      store_spec("          - row: { store: 計 }\n            style: sub\n"),
    ).sheets[0]
  let footer = sheet.cells.filter(cell => cell.pos.row == 6)
  assert_eq(footer.length(), 6)
  assert_true(footer.iter().all(cell => cell.style is Some(_)))
}

///|
test "the other totals, and min and max under their _xlfn names" {
  let cells = footer_cells(
    (
      #|          - row: { cy: { total: average }, py: { total: min } }
      #|          - by: branch
      #|            rows: [{ row: { cy: { total: max }, py: { total: average } } }]
    ),
  )
  assert_eq(formula_at(cells, "D6"), Some("AVERAGE(D2:D5)"))
  assert_eq(formula_at(cells, "E6"), Some("MIN(E2:E5)"))
  assert_eq(
    formula_at(cells, "D7"),
    Some("_xlfn.MAXIFS(D2:D5,A2:A5,\"=大阪\")"),
  )
  assert_eq(
    formula_at(cells, "E7"),
    Some("AVERAGEIFS(E2:E5,A2:A5,\"=大阪\")"),
  )
}

///|
test "a listed order may not leave out a value the data holds" {
  assert_eq(
    schema_message(
      store_spec(
        "          - by: branch\n            order: [東京]\n            rows: [{ row: { store: x } }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' footer group 'branch' 'order' leaves out '大阪', which the data holds; its rows would be in no subtotal",
    ),
  )
}

///|
test "text spells only an enclosing group's value" {
  assert_eq(
    schema_message(
      store_spec("          - row: { store: \"{{branch}} 計\" }\n"),
    ),
    Some(
      "spec.yaml: layout 'A1' footer row 6 column 'store' spells '{{branch}}', but text can only spell a group's value, and there is no enclosing 'by' group",
    ),
  )
  assert_eq(
    schema_message(
      store_spec(
        "          - by: branch\n            rows: [{ row: { store: \"{{cy}}\" } }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' footer row 6 column 'store' spells '{{cy}}', but text can only spell a group's value, and the groups here are 'branch'",
    ),
  )
}

///|
test "a footer's entries, groups and totals are checked" {
  let refused = (footer : String) => schema_message(store_spec(footer))
  assert_eq(
    refused("          - { store: x }\n"),
    Some(
      "spec.yaml: a layout 'A1' footer entry is a 'row', or a group with 'by'",
    ),
  )
  assert_eq(
    refused("          - row: { shop: x }\n"),
    Some(
      "spec.yaml: a layout 'A1' footer row names 'shop', which is not a column of the layout",
    ),
  )
  assert_eq(
    refused(
      "          - by: ratio\n            rows: [{ row: { store: x } }]\n",
    ),
    Some(
      "spec.yaml: layout 'A1' footer group 'ratio' must name a column the data fills (one without a 'formula')",
    ),
  )
  assert_eq(
    refused(
      "          - by: branch\n            rows:\n              - by: branch\n                rows: [{ row: { store: x } }]\n",
    ),
    Some("spec.yaml: layout 'A1' footer group 'branch' is nested inside itself"),
  )
  assert_eq(
    refused(
      "          - by: branch\n            order: random\n            rows: []\n",
    ),
    Some(
      "spec.yaml: layout 'A1' footer group 'branch' 'order' must be 'data', 'asc', 'desc', or a list of values",
    ),
  )
  assert_eq(
    refused(
      "          - by: branch\n            order: [東京, 東京]\n            rows: []\n",
    ),
    Some(
      "spec.yaml: layout 'A1' footer group 'branch' 'order' lists '東京' twice",
    ),
  )
  assert_eq(
    refused("          - row: { cy: { total: median } }\n"),
    Some(
      "spec.yaml: layout 'A1' footer row 6 column 'cy' 'total' must be 'sum', 'count', 'average', 'min', or 'max'",
    ),
  )
}

///|
test "a group needs data to take values from, unless it lists them" {
  let spec = layout_spec(
    "      - at: A1\n        rows: 2\n        columns: [{ name: a }, { name: b }]\n        footer:\n          - by: a\n            rows: [{ row: { b: { total: sum } } }]\n",
  )
  assert_eq(
    schema_message(spec),
    Some(
      "spec.yaml: layout 'A1' footer group 'a' takes its values from the layout's data, and the layout reads none; list them in 'order'",
    ),
  )
}
