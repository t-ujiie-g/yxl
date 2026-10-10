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
test "a named layout is a defined name over its table, and each column over its body" {
  let workbook = load_ok(named_spec(""))
  let names = workbook.defined_names.map(name => {
    guard name.refers_to is Formula(formula~, ..) else { "" }
    "\{name.name}=\{formula}"
  })
  assert_eq(names, [
    "店舗='実績'!$A$1:$E$4", "店舗.branch='実績'!$A$2:$A$4", "店舗.store='実績'!$B$2:$B$4",
    "店舗.cy='実績'!$C$2:$C$4", "店舗.py='実績'!$D$2:$D$4", "店舗.ratio='実績'!$E$2:$E$4",
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

///|
/// A report sheet, declared before the data sheet it reads, over a named layout
/// whose length follows its data.
fn reach_spec(report : String) -> String {
  (
    #|sheets:
    #|  - name: 報告
    #|
  ) +
  report +
  (
    #|  - name: 店舗別
    #|    layouts:
    #|      - at: A1
    #|        name: 店舗
    #|        values: [[東京, 直営, 520], [大阪, FC, 410], [福岡, 直営, 220]]
    #|        columns:
    #|          - { name: branch, header: 支店 }
    #|          - { name: channel, header: 区分 }
    #|          - { name: cy, header: 当年 }
    #|        footer:
    #|          - row: { branch: 計, cy: { total: sum } }
    #|
  )
}

///|
test "a chart on an earlier sheet plots a layout's columns by name" {
  let chart = load_ok(
      reach_spec(
        "    charts:\n      - at: A1\n        type: column\n        series:\n          - { name: 当年, values: 店舗.cy, categories: 店舗.branch }\n",
      ),
    ).sheets[0].charts[0]
  let series = chart.series[0]
  assert_eq(series.values.sheet, Some("店舗別"))
  assert_eq(series.values.range.to_a1(), "C2:C4")
  assert_eq(series.categories.map(range => range.range.to_a1()), Some("A2:A4"))
}

///|
test "a validation takes its list from a layout's column" {
  let validation = load_ok(
      reach_spec(
        "    validations:\n      - { at: A1:A9, list: { from: 店舗.branch } }\n",
      ),
    ).sheets[0].validations[0]
  guard validation.rule is ListFrom(range) else { fail("not a list") }
  assert_eq(range.range.to_a1(), "A2:A4")
}

///|
test "a pivot's source may be a whole layout: its header row and body" {
  let pivot = load_ok(
      reach_spec(
        "    pivots:\n      - at: A1:D20\n        source: 店舗\n        rows: [支店]\n        values: [{ field: 当年 }]\n",
      ),
    ).sheets[0].pivots[0]
  assert_eq(pivot.source.range.to_a1(), "A1:C4")
}

///|
test "a range on the layout's own sheet may name it: a table, a rule, a validation" {
  let source =
    #|sheets:
    #|  - name: S
    #|    layouts:
    #|      - at: A1
    #|        name: t
    #|        values: [[a, 1], [b, 2]]
    #|        columns: [{ name: key, header: キー }, { name: v, header: 値 }]
    #|    tables: [{ at: t, name: Stores }]
    #|    validations: [{ at: t.v, whole: { at_least: 0 } }]
    #|    conditional: [{ at: t.v, duplicate: true, style: { font: { bold: true } } }]
    #|
  let sheet = load_ok(source).sheets[0]
  assert_eq(sheet.tables[0].at.to_a1(), "A1:B3")
  assert_eq(sheet.validations[0].at.to_a1(), "B2:B3")
  assert_eq(sheet.conditional_formats[0].at.to_a1(), "B2:B3")
}

///|
test "an anchor may follow a layout, footer included" {
  let source =
    #|sheets:
    #|  - name: S
    #|    layouts:
    #|      - at: B2
    #|        name: first
    #|        values: [[1], [2], [3]]
    #|        columns: [{ name: v, header: 値 }]
    #|        footer: [{ row: { v: { total: sum } } }]
    #|      - at: { below: first, gap: 2 }
    #|        rows: 1
    #|        columns: [{ name: w, header: 次 }]
    #|    charts:
    #|      - at: { below: first }
    #|        type: column
    #|        series: [{ values: first.v }]
    #|
  let sheet = load_ok(source).sheets[0]
  let header = sheet.cells.filter(cell => cell.value == Text("次"))
  assert_eq(header.map(cell => cell.pos.to_a1()), ["B9"])
  assert_eq(sheet.charts[0].at.to_a1(), "B8")
}

///|
test "names that reach nothing, or reach too far, are refused" {
  assert_eq(
    schema_message(
      reach_spec(
        "    charts:\n      - at: A1\n        type: column\n        series: [{ values: 店舗.py }]\n",
      ),
    ),
    Some(
      "spec.yaml: chart at 'A1' series 'values' '店舗.py' is neither a range nor a named layout or one of its columns (layouts: '店舗')",
    ),
  )
  assert_eq(
    schema_message(
      reach_spec(
        "    validations: [{ at: 店舗.cy, whole: { at_least: 0 } }]\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'at' '店舗.cy' names a layout on sheet '店舗別', not this one",
    ),
  )
  assert_eq(
    schema_message(
      reach_spec(
        "    images: []\n    charts:\n      - at: { below: 店舗 }\n        type: column\n        series: [{ values: 店舗.cy }]\n",
      ),
    ),
    Some(
      "spec.yaml: chart 'at' follows layout '店舗', which is on sheet '店舗別', not this one",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    layouts:\n      - { at: { below: later }, rows: 1, columns: [{ name: a }] }\n      - { at: A9, name: later, rows: 1, columns: [{ name: b }] }\n",
    ),
    Some(
      "spec.yaml: layout 'at' follows layout 'later', which no layout declared before it is called",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    charts:\n      - at: { beneath: x }\n        type: column\n        series: [{ values: A1:A2 }]\n",
    ),
    Some(
      "spec.yaml: unknown key 'beneath' in chart 'at' (expected 'below' or 'gap')",
    ),
  )
}
