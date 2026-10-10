///|
test "load rejects invalid column/row selectors and a missing 'at', and keeps empty bands out" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: A1\n        style: { font: { bold: true } }\n",
    ),
    Some("spec.yaml: 'A1' is not a valid column"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: F-D\n        format: \"0\"\n",
    ),
    Some("spec.yaml: column range 'F-D' is reversed"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    rows:\n      - at: 0\n        format: \"0\"\n",
    ),
    Some("spec.yaml: '0' is not a valid row"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    rows:\n      - format: \"0\"\n"),
    Some("spec.yaml: a row entry is missing required key 'at'"),
  )
  let workbook = load_ok("sheets:\n  - name: S\n    columns:\n      - at: B\n")
  assert_eq(workbook.sheets[0].columns.length(), 0)
}

///|
test "a band selector must be a scalar, and a size must be a number" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: [B]\n        width: 10\n",
    ),
    Some("spec.yaml: a column 'at' must be text or a number"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: B\n        width: wide\n",
    ),
    Some("spec.yaml: column 'B' width must be a number"),
  )
}

///|
test "load parses merges, column widths, and row heights" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: B
      #|        width: 18
      #|      - at: D-F
      #|        style: { font: { bold: true } }
      #|        width: 10
      #|    rows:
      #|      - at: 1
      #|        height: 24
      #|    merges:
      #|      - A1:C1
      #|      - B2:B4
      #|
    ),
  )
  let sheet = workbook.sheets[0]
  assert_eq(sheet.columns.length(), 2)
  assert_eq((sheet.columns[0].first, sheet.columns[0].last), (2, 2))
  assert_eq(sheet.columns[0].size, Some(18.0))
  assert_eq(sheet.columns[0].style, None)
  assert_eq((sheet.columns[1].first, sheet.columns[1].last), (4, 6))
  assert_eq(sheet.columns[1].size, Some(10.0))
  assert_eq(sheet.columns[1].style.unwrap().font.unwrap().bold, Some(true))
  assert_eq(sheet.rows.length(), 1)
  assert_eq(sheet.rows[0].size, Some(24.0))
  assert_eq(sheet.merges, [
    {
      top_left: @units.CellRef(col=1, row=1),
      bottom_right: @units.CellRef(col=3, row=1),
    },
    {
      top_left: @units.CellRef(col=2, row=2),
      bottom_right: @units.CellRef(col=2, row=4),
    },
  ])
}

///|
test "a merge range's corners are canonicalized regardless of order" {
  let workbook = load_ok("sheets:\n  - name: S\n    merges:\n      - C3:A1\n")
  assert_eq(workbook.sheets[0].merges, [
    {
      top_left: @units.CellRef(col=1, row=1),
      bottom_right: @units.CellRef(col=3, row=3),
    },
  ])
}

///|
test "load rejects bad merge ranges and a size key on the wrong axis" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    merges:\n      - A1\n"),
    Some("spec.yaml: merge range 'A1' must be 'TopLeft:BottomRight'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    merges:\n      - A1:Z0\n"),
    Some(
      "spec.yaml: 'Z0' is not a valid A1 cell reference in merge range 'A1:Z0'",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    rows:\n      - at: 1\n        width: 10\n",
    ),
    Some(
      "spec.yaml: unknown key 'width' in row '1' (expected 'at', 'style', 'format', 'height', 'hidden', or 'group')",
    ),
  )
}

///|
test "load parses band visibility and outline grouping" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: B-C
      #|        group: 1
      #|        hidden: true
      #|      - at: D
      #|        width: 12
      #|        group: 0
      #|    rows:
      #|      - at: 2-4
      #|        group: 2
      #|        hidden: false
      #|
    ),
  )
  let sheet = workbook.sheets[0]
  assert_eq(sheet.columns[0], {
    first: 2,
    last: 3,
    style: None,
    size: None,
    hidden: Some(true),
    outline_level: Some(1),
  })
  assert_eq(sheet.columns[1], {
    first: 4,
    last: 4,
    style: None,
    size: Some(12.0),
    hidden: None,
    outline_level: Some(0),
  })
  assert_eq(sheet.rows[0], {
    first: 2,
    last: 4,
    style: None,
    size: None,
    hidden: Some(false),
    outline_level: Some(2),
  })
}

///|
test "load rejects a bad 'hidden' flag and an out-of-range or fractional 'group'" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: B\n        hidden: yes please\n",
    ),
    Some("spec.yaml: column 'B' hidden must be true or false"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    rows:\n      - at: 1\n        group: 8\n",
    ),
    Some("spec.yaml: row '1' group must be between 0 and 7"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    rows:\n      - at: 1\n        group: -1\n",
    ),
    Some("spec.yaml: row '1' group must be between 0 and 7"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: B\n        group: 1.5\n",
    ),
    Some("spec.yaml: column 'B' group must be a whole number"),
  )
}
