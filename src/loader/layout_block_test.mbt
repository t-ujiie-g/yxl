///|
/// A year-on-year block, placed by `layout`'s columns.
fn block_spec(layout : String) -> String {
  (
    #|defs:
    #|  styles:
    #|    weak: { font: { color: "C00000" } }
    #|  blocks:
    #|    yoy:
    #|      columns:
    #|        - { name: cy, header: 当年, format: "#,##0" }
    #|        - { name: py, header: 前年, format: "#,##0" }
    #|        - name: ratio
    #|          header: 前年比
    #|          formula: "{{cy}}/{{py}}-1"
    #|          conditional: [{ cell: { less_than: 0 }, style: weak }]
    #|sheets:
    #|  - name: S
    #|    layouts:
    #|      - at: A1
    #|
  ) +
  layout
}

///|
test "blocks load to exactly what their columns written out load to" {
  let blocks = load_ok(
    block_spec(
      (
        #|        values: [[東日本, 520, 480, 150, 140]]
        #|        columns:
        #|          - { name: item, header: 部門 }
        #|          - { block: yoy, as: sales, header: 売上 }
        #|          - { block: yoy, as: gross, header: 粗利 }
      ),
    ),
  )
  let written_out = load_ok(
    block_spec(
      (
        #|        values: [[東日本, 520, 480, 150, 140]]
        #|        columns:
        #|          - { name: item, header: 部門 }
        #|          - { name: sales_cy, header: [売上, 当年], format: "#,##0" }
        #|          - { name: sales_py, header: [売上, 前年], format: "#,##0" }
        #|          - name: sales_ratio
        #|            header: [売上, 前年比]
        #|            formula: "{{sales_cy}}/{{sales_py}}-1"
        #|            conditional: [{ cell: { less_than: 0 }, style: weak }]
        #|          - { name: gross_cy, header: [粗利, 当年], format: "#,##0" }
        #|          - { name: gross_py, header: [粗利, 前年], format: "#,##0" }
        #|          - name: gross_ratio
        #|            header: [粗利, 前年比]
        #|            formula: "{{gross_cy}}/{{gross_py}}-1"
        #|            conditional: [{ cell: { less_than: 0 }, style: weak }]
      ),
    ),
  )
  assert_eq(blocks, written_out)
  assert_eq(merged(blocks.sheets[0]), ["A1:A2", "B1:D1", "E1:G1"])
  assert_eq(blocks.sheets[0].formulas[1].formula, "E3/F3-1")
}

///|
test "an instance reaches another by 'as.name', and the layout by a bare name" {
  let sheet = load_ok(
      block_spec(
        (
          #|        rows: 1
          #|        columns:
          #|          - { name: rate }
          #|          - { block: yoy, as: sales }
          #|          - { name: share, formula: "{{sales.cy}}*{{rate}}" }
        ),
      ),
    ).sheets[0]
  assert_eq(sheet.formulas.map(range => range.formula), ["B2/C2-1", "B2*A2"])
}

///|
test "'as' defaults to the block's name, and 'fields' maps a CSV per instance" {
  let sheet = load_ok(
      block_spec(
        (
          #|        csv: sales.csv
          #|        columns:
          #|          - block: yoy
          #|            fields: { cy: 売上当年, py: 売上前年 }
        ),
      ),
      files={ "sales.csv": "売上前年,売上当年\n480,520\n" },
    ).sheets[0]
  let cells = written(sheet)
  assert_eq(cells.get("A2"), Some((Number(520.0), false)))
  assert_eq(cells.get("B2"), Some((Number(480.0), false)))
  assert_eq(sheet.formulas[0].formula, "A2/B2-1")
}

///|
test "a footer names an instance's column by its qualified name" {
  let sheet = load_ok(
      block_spec(
        (
          #|        values: [[520, 480], [310, 330]]
          #|        columns:
          #|          - { block: yoy, as: sales }
          #|        footer:
          #|          - row:
          #|              sales.cy: { total: sum }
          #|              sales.ratio: { formula: "{{sales.cy}}/{{sales.py}}-1" }
        ),
      ),
    ).sheets[0]
  let totals = sheet.cells.filter(cell => cell.pos.row == 4)
  assert_eq(totals.map(cell => cell.value), [
    Formula(formula="SUM(A2:A3)", cached=None),
    Formula(formula="A4/B4-1", cached=None),
  ])
}

///|
test "a block definition holds columns, and places no other block" {
  let refused = (defs : String) => {
    schema_message("defs:\n  blocks:\n    yoy:\n\{defs}sheets:\n  - name: S\n")
  }
  assert_eq(
    refused("      columns: []\n"),
    Some("spec.yaml: block 'yoy' needs at least one column"),
  )
  assert_eq(
    refused("      columns: [{ name: a }]\n      header: x\n"),
    Some("spec.yaml: unknown key 'header' in block 'yoy' (expected 'columns')"),
  )
  assert_eq(
    refused("      columns: [{ block: yoy }]\n"),
    Some("spec.yaml: block 'yoy' places another block; blocks do not nest"),
  )
}

///|
test "an instance names a declared block, once, and keys it knows" {
  let refused = (columns : String) => {
    schema_message(block_spec("        rows: 1\n        columns:\n\{columns}"))
  }
  assert_eq(
    refused("          - { block: mom }\n"),
    Some(
      "spec.yaml: layout 'A1' places block 'mom', which 'defs.blocks' does not declare (declared: 'yoy')",
    ),
  )
  assert_eq(
    refused("          - { block: yoy }\n          - { block: yoy }\n"),
    Some(
      "spec.yaml: layout 'A1' places two blocks as 'yoy'; give one of them another 'as'",
    ),
  )
  assert_eq(
    refused(
      "          - { block: yoy, as: sales }\n          - { name: sales }\n",
    ),
    Some(
      "spec.yaml: layout 'A1' column 'sales' has the name of a block placed in the same layout",
    ),
  )
  assert_eq(
    refused("          - { block: yoy, width: 9 }\n"),
    Some(
      "spec.yaml: unknown key 'width' in layout 'A1' block 'yoy' (expected 'block', 'as', 'header', or 'fields')",
    ),
  )
  assert_eq(
    refused("          - { block: yoy, fields: { ratio: x } }\n"),
    Some(
      "spec.yaml: layout 'A1' 'yoy' fields names 'ratio', which is not a column of block 'yoy' the data fills ('cy', 'py', or 'ratio')",
    ),
  )
}
