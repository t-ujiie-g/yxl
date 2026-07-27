// Schema tests for a sheet's `sparklines:`.

///|
/// The sole sparkline group a spec loads.
fn loaded_sparkline(body : String) -> @model.SparklineGroup raise {
  let groups = load_ok(sheet_spec("    sparklines:\n" + body)).sheets[0].sparklines
  assert_eq(groups.length(), 1)
  groups[0]
}

///|
test "a sparkline loads its cell and data, leaving the rest to defaults" {
  let group = loaded_sparkline("      - at: F2\n        data: B2:E2\n")
  assert_eq(group.kind, Line)
  assert_eq(group.cells.length(), 1)
  assert_eq(group.cells[0].at.to_a1(), "F2")
  assert_eq(group.cells[0].data.sheet, None)
  assert_eq(group.cells[0].data.range.to_a1(), "B2:E2")
  assert_eq(group.markers, false)
  assert_eq(group.high, false)
  assert_eq(group.low, false)
  assert_eq(group.min, None)
  assert_eq(group.max, None)
  assert_eq(group.weight, None)
  assert_eq(group.color, None)
  assert_eq(group.axis, false)
}

///|
test "a sparkline group loads its kind, emphasis, bounds, colours, and axis" {
  let workbook = load_ok(
    sheet_spec(
      "    sparklines:\n" +
      (
        #|      - at: F2
        #|        data: "'Q3 data'!B2:E2"
        #|        type: column
        #|        high: true
        #|        low: true
        #|        min: 0
        #|        max: 20
        #|        color: "1F77B4"
        #|        colors: { high: "CC0000", low: "0000CC" }
        #|        axis: true
        #|
      ),
    ) +
    "  - name: \"Q3 data\"\n",
  )
  let groups = workbook.sheets[0].sparklines
  assert_eq(groups.length(), 1)
  let group = groups[0]
  assert_eq(group.kind, Column)
  assert_eq(group.cells[0].data.sheet, Some("Q3 data"))
  assert_eq(group.cells[0].data.range.to_a1(), "B2:E2")
  assert_eq(group.high, true)
  assert_eq(group.low, true)
  assert_eq(group.min, Some(0))
  assert_eq(group.max, Some(20))
  assert_eq(group.color.unwrap().hex(), "1F77B4")
  assert_eq(group.high_color.unwrap().hex(), "CC0000")
  assert_eq(group.low_color.unwrap().hex(), "0000CC")
  assert_eq(group.markers_color, None)
  assert_eq(group.axis, true)
}

///|
test "a line sparkline may dot its points and weigh its line" {
  let group = loaded_sparkline(
    "      - at: F2\n        data: B2:E2\n        markers: true\n        weight: 1.25\n        colors: { markers: \"333333\" }\n",
  )
  assert_eq(group.markers, true)
  assert_eq(group.weight, Some(1.25))
  assert_eq(group.markers_color.unwrap().hex(), "333333")
}

///|
test "a group places several sparklines through 'cells'" {
  let group = loaded_sparkline(
    (
      #|      - type: win_loss
      #|        cells:
      #|          - { at: F2, data: B2:E2 }
      #|          - { at: F3, data: B3:E3 }
      #|
    ),
  )
  assert_eq(group.kind, WinLoss)
  assert_eq(group.cells.length(), 2)
  assert_eq(group.cells[1].at.to_a1(), "F3")
  assert_eq(group.cells[1].data.range.to_a1(), "B3:E3")
}

///|
test "a sparkline group must be placed exactly one way" {
  assert_eq(
    schema_message(sheet_spec("    sparklines:\n      - at: F2\n")),
    Some("spec.yaml: sparkline at 'F2' is missing required key 'data'"),
  )
  assert_eq(
    schema_message(sheet_spec("    sparklines:\n      - data: B2:E2\n")),
    Some("spec.yaml: a sparkline group has 'data' but no 'at'"),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        cells:\n          - { at: F3, data: B3:E3 }\n",
      ),
    ),
    Some(
      "spec.yaml: sparkline at 'F2' mixes 'at'/'data' with 'cells' — place the group one way",
    ),
  )
  assert_eq(
    schema_message(sheet_spec("    sparklines:\n      - type: line\n")),
    Some(
      "spec.yaml: a sparkline group places nothing (expected 'at' with 'data', or 'cells')",
    ),
  )
}

///|
test "a 'cells' entry needs both halves and nothing else" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - cells:\n          - { data: B2:E2 }\n",
      ),
    ),
    Some("spec.yaml: a sparkline 'cells' entry is missing required key 'at'"),
  )
  assert_eq(
    schema_message(
      sheet_spec("    sparklines:\n      - cells:\n          - { at: F2 }\n"),
    ),
    Some("spec.yaml: a sparkline 'cells' entry is missing required key 'data'"),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - cells:\n          - { at: F2, data: B2:E2, style: 3 }\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'style' in a sparkline 'cells' entry (expected 'at' or 'data')",
    ),
  )
}

///|
test "the markers the backend cannot switch on are refused with the reason" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        negative: true\n",
      ),
    ),
    Some(
      "spec.yaml: sparkline at 'F2' sets 'negative', a marker the Excel backend cannot switch on yet — 'high', 'low', and 'markers' are available",
    ),
  )
}

///|
test "markers and weight belong to a line sparkline" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        type: column\n        markers: true\n",
      ),
    ),
    Some(
      "spec.yaml: sparkline at 'F2' sets 'markers', which only a line sparkline draws (this one is 'column')",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        type: win_loss\n        weight: 2\n",
      ),
    ),
    Some(
      "spec.yaml: sparkline at 'F2' sets 'weight', which only a line sparkline has (this one is 'win_loss')",
    ),
  )
}

///|
test "bounds are whole, ordered; a weight is positive; kinds are named" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        min: 1.5\n",
      ),
    ),
    Some(
      "spec.yaml: sparkline at 'F2' 'min' must be a whole number (the Excel backend takes no finer bound)",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        min: 10\n        max: 5\n",
      ),
    ),
    Some("spec.yaml: sparkline at 'F2' has 'min' 10 above 'max' 5"),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        weight: 0\n",
      ),
    ),
    Some(
      "spec.yaml: sparkline at 'F2' 'weight' must be above 0 (points), not 0",
    ),
  )
  guard schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        type: bars\n",
      ),
    )
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_eq(
    message, "spec.yaml: unknown sparkline type 'bars' in sparkline at 'F2' (expected 'line', 'column', or 'win_loss')",
  )
}

///|
test "a sparkline plotting an undeclared sheet is a diagnostic" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: Elsewhere!B2:E2\n",
      ),
    ),
    Some(
      "spec.yaml: sparkline at 'F2' on sheet 'S' plots sheet 'Elsewhere', which is not declared",
    ),
  )
}

///|
test "a sparkline group rejects an unknown key" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        style: 12\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'style' in sparkline at 'F2' (expected 'at', 'data', 'cells', 'type', 'markers', 'high', 'low', 'min', 'max', 'weight', 'color', 'colors', or 'axis')",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    sparklines:\n      - at: F2\n        data: B2:E2\n        colors: { series: \"1F77B4\" }\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'series' in sparkline at 'F2' 'colors' (expected 'markers', 'high', or 'low')",
    ),
  )
}
