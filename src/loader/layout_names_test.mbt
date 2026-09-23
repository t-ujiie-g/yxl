///|
/// A named store layout on `実績`, with `rest` appended to the document.
fn named_spec(rest : String) -> String {
  (
    #|sheets:
    #|  - name: 実績
    #|    layouts:
    #|      - at: A1
    #|        name: 店舗
    #|        values:
    #|          - [東京, 銀座, 520, 480]
    #|          - [大阪, 梅田, 410, 430]
    #|          - [東京, 新宿, 310, 300]
    #|        columns:
    #|          - { name: branch, header: 支店 }
    #|          - { name: store, header: 店舗 }
    #|          - { name: cy, header: 当年 }
    #|          - { name: py, header: 前年 }
    #|          - { name: ratio, header: 比, formula: "{{cy}}/{{py}}-1" }
    #|  - name: 集計
    #|    cells:
    #|      A1: { formula: "SUM(店舗.cy)" }
    #|
  ) +
  rest
}

///|
test "each column of a named layout is a defined name over its body" {
  let workbook = load_ok(named_spec(""))
  let names = workbook.defined_names.map(name => {
    guard name.refers_to is Formula(formula~, ..) else { "" }
    "\{name.name}=\{formula}"
  })
  assert_eq(names, [
    "店舗.branch='実績'!$A$2:$A$4", "店舗.store='実績'!$B$2:$B$4", "店舗.cy='実績'!$C$2:$C$4",
    "店舗.py='実績'!$D$2:$D$4", "店舗.ratio='実績'!$E$2:$E$4",
  ])
}

///|
test "an override finds its row by the data's values, or by number" {
  let by_meaning = load_ok(
    named_spec(
      (
        #|overrides:
        #|  - at: { layout: 店舗, column: ratio, where: { branch: 東京, store: 新宿 } }
        #|    formula: "=0"
        #|    reason: 新店
        #|  - at: { layout: 店舗, column: cy, row: 2 }
        #|    value: 999
      ),
    ),
  )
  let targets = by_meaning.overrides.map(entry => {
    "\{entry.sheet}!\{entry.at.to_a1()}"
  })
  assert_eq(targets, ["実績!E4", "実績!C3"])
}

///|
test "an override by meaning must find exactly one row" {
  let refused = (at : String) => {
    schema_message(named_spec("overrides:\n  - at: \{at}\n    value: 1\n"))
  }
  assert_eq(
    refused("{ layout: 店舗, column: cy, where: { branch: 東京 } }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' 'where' matches 2 rows of the data; it must find exactly one",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: cy, where: { branch: 福岡 } }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' 'where' matches 0 rows of the data; it must find exactly one",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: cy, where: { ratio: 0 } }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' 'where' names 'ratio', which is not a column the layout's data fills",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: cy, row: 4 }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' 'row' is 4, but the body has rows 1 to 3",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: cy }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' needs exactly one of 'where' or 'row' to find its row",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: sales, row: 1 }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' names column 'sales', which the layout does not have",
    ),
  )
  assert_eq(
    refused("{ layout: 支店, column: cy, row: 1 }"),
    Some(
      "spec.yaml: override 'at' names layout '支店', which no layout is called (named: '店舗')",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, row: 1 }"),
    Some(
      "spec.yaml: override 'at' given by layout needs both 'layout' and 'column'",
    ),
  )
}

///|
test "an override written before the sheets still finds a layout" {
  let source =
    #|overrides:
    #|  - at: { layout: t, column: a, row: 1 }
    #|    value: 2
    #|sheets:
    #|  - name: S
    #|    layouts:
    #|      - { at: A1, name: t, rows: 1, columns: [{ name: a }] }
    #|    cells:
    #|      A1: 1
    #|
  assert_eq(load_ok(source).overrides[0].at.to_a1(), "A1")
}

///|
test "a layout's name is one Excel accepts, and one only" {
  let spec = (name : String) => {
    layout_spec(
      "      - at: A1\n        name: \{name}\n        rows: 1\n        columns: [{ name: a }]\n",
    )
  }
  assert_eq(
    schema_message(spec("1st")),
    Some(
      "spec.yaml: layout 'A1' 'name' '1st' is not a name Excel accepts: letters, digits, '_' and '.', starting with a letter or '_', and not a cell reference",
    ),
  )
  assert_eq(
    schema_message(spec("ab12")),
    Some(
      "spec.yaml: layout 'A1' 'name' 'ab12' is not a name Excel accepts: letters, digits, '_' and '.', starting with a letter or '_', and not a cell reference",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - { at: A1, name: T, rows: 1, columns: [{ name: a }] }\n      - { at: C1, name: t, rows: 1, columns: [{ name: b }] }\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'C1' 'name' 't' is already the name of another layout",
    ),
  )
}

///|
test "defined names and table names may not repeat, ignoring case" {
  assert_eq(
    schema_message(
      "defs:\n  values: { rate: 1 }\n  formulas: { RATE: \"1+1\" }\nsheets:\n  - name: S\n",
    ),
    Some(
      "spec.yaml: the defined name 'RATE' is also the defined name 'rate'; Excel keeps one namespace for names and tables, ignoring case",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    layouts:\n      - { at: A1, name: t, rows: 1, columns: [{ name: a }] }\n    cells: { C1: x, C2: 1 }\n    tables: [{ at: C1:C2, name: t.a }]\n",
    ),
    Some(
      "spec.yaml: the table 't.a' is also the defined name 't.a'; Excel keeps one namespace for names and tables, ignoring case",
    ),
  )
}
