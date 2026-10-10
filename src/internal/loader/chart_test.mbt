///|
/// A sheet carrying a chart, plus a second sheet a chart may plot.
fn chart_spec(body : String) -> String {
  sheet_spec("    charts:\n" + body) +
  "  - name: Data\n    cells:\n      A1: APAC\n"
}

///|
/// The sole chart a spec loads.
fn loaded_chart(body : String) -> @model.Chart raise {
  let charts = load_ok(chart_spec(body)).sheets[0].charts
  assert_eq(charts.length(), 1)
  charts[0]
}

///|
/// The smallest chart that loads: one series, no trimmings.
const MINIMAL_CHART : String = "      - at: D2\n        type: column\n        series:\n          - values: B2:B4\n"

///|
test "a chart loads its anchor, kind, and one series" {
  let chart = loaded_chart(MINIMAL_CHART)
  assert_eq(chart.at.to_a1(), "D2")
  assert_eq(chart.kind, Column)
  assert_eq(chart.series.length(), 1)
  assert_eq(chart.series[0].values.sheet, None)
  assert_eq(chart.series[0].values.range.top_left.to_a1(), "B2")
  assert_eq(chart.series[0].values.range.bottom_right.to_a1(), "B4")
  assert_eq(chart.series[0].categories, None)
  assert_eq(chart.series[0].name, None)
  assert_eq(chart.title, None)
  assert_eq(chart.legend, None)
  assert_eq(chart.size, None)
  assert_eq(chart.x_axis, None)
  assert_eq(chart.y_axis, None)
}

///|
test "a chart loads its title, legend, size, and axes" {
  let chart = loaded_chart(
    (
      #|      - at: D2
      #|        type: line
      #|        title: Revenue by region
      #|        legend: top_right
      #|        size: { width: 520, height: 300 }
      #|        x_axis: { title: Region }
      #|        y_axis: { title: Amount, min: 0, max: 4000000 }
      #|        series:
      #|          - values: B2:B4
      #|
    ),
  )
  assert_eq(chart.kind, Line)
  assert_eq(chart.title, Some("Revenue by region"))
  assert_eq(chart.legend, Some(TopRight))
  assert_eq(chart.size, Some({ width: 520, height: 300, }))
  assert_eq(
    chart.x_axis,
    Some({ title: Some("Region"), min: None, max: None, }),
  )
  assert_eq(
    chart.y_axis,
    Some({ title: Some("Amount"), min: Some(0.0), max: Some(4000000.0), }),
  )
}

///|
test "every chart kind and legend position a spec may write is accepted" {
  for
    kind in [
      "column", "column_stacked", "column_percent_stacked", "bar", "bar_stacked",
      "bar_percent_stacked", "line", "area", "area_stacked", "area_percent_stacked",
      "pie", "doughnut", "scatter", "radar",
    ] {
    assert_eq(
      schema_message(
        chart_spec(
          "      - at: D2\n        type: \{kind}\n        series:\n          - values: B2:B4\n",
        ),
      ),
      None,
    )
  }
  for position in ["bottom", "top", "left", "right", "top_right", "none"] {
    assert_eq(
      schema_message(
        chart_spec(
          "      - at: D2\n        type: column\n        legend: \{position}\n        series:\n          - values: B2:B4\n",
        ),
      ),
      None,
    )
  }
}

///|
test "an unknown chart kind is a diagnostic listing the ones there are" {
  guard schema_message(
      chart_spec(
        "      - at: D2\n        type: waterfall\n        series:\n          - values: B2:B4\n",
      ),
    )
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_true(
    message.has_prefix(
      "spec.yaml: unknown chart type 'waterfall' in chart at 'D2'",
    ),
  )
  assert_true(message.contains("'column'"))
  assert_true(message.contains("'radar'"))
}

///|
test "a series names itself outright or from a cell" {
  let chart = loaded_chart(
    "      - at: D2\n        type: column\n        series:\n          - values: B2:B4\n            name: Revenue\n          - values: C2:C4\n            name_from: Data!C1\n",
  )
  assert_eq(chart.series[0].name, Some(Literal("Revenue")))
  guard chart.series[1].name is Some(FromCell(sheet~, at~)) else {
    fail("expected a name read from a cell")
  }
  assert_eq(sheet, Some("Data"))
  assert_eq(at.to_a1(), "C1")
}

///|
test "a series cannot be called two things at once" {
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        series:\n          - values: B2:B4\n            name: Revenue\n            name_from: B1\n",
      ),
    ),
    Some(
      "spec.yaml: chart at 'D2' series sets both 'name' and 'name_from'; a series is called one thing",
    ),
  )
}

///|
/// The backend reads a series name holding `!` as a reference to a cell, so a
/// literal that looks like one would quietly become a lookup.
test "a literal series name that looks like a reference is refused" {
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        series:\n          - values: B2:B4\n            name: Data!B1\n",
      ),
    ),
    Some(
      "spec.yaml: chart at 'D2' series 'name' 'Data!B1' looks like a cell reference; use 'name_from' to read the name from a cell",
    ),
  )
}

///|
test "a chart plotting an undeclared sheet is a diagnostic" {
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        series:\n          - values: Missing!B2:B4\n",
      ),
    ),
    Some(
      "spec.yaml: chart at 'D2' on sheet 'S' plots sheet 'Missing', which is not declared",
    ),
  )
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        series:\n          - values: B2:B4\n            name_from: Missing!B1\n",
      ),
    ),
    Some(
      "spec.yaml: chart at 'D2' on sheet 'S' names a series from sheet 'Missing', which is not declared",
    ),
  )
}

///|
test "a chart needs a type, a series, and something to plot" {
  assert_eq(
    schema_message(
      chart_spec("      - at: D2\n        series:\n          - values: B2:B4\n"),
    ),
    Some("spec.yaml: chart at 'D2' is missing required key 'type'"),
  )
  assert_eq(
    schema_message(chart_spec("      - at: D2\n        type: column\n")),
    Some("spec.yaml: chart at 'D2' is missing required key 'series'"),
  )
  assert_eq(
    schema_message(
      chart_spec("      - at: D2\n        type: column\n        series: []\n"),
    ),
    Some(
      "spec.yaml: chart at 'D2' 'series' is empty; a chart plots at least one",
    ),
  )
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        series:\n          - categories: A2:A4\n",
      ),
    ),
    Some("spec.yaml: chart at 'D2' series is missing required key 'values'"),
  )
  assert_eq(
    schema_message(
      chart_spec(
        "      - type: column\n        series:\n          - values: B2:B4\n",
      ),
    ),
    Some("spec.yaml: a chart is missing required key 'at'"),
  )
}

///|
test "a chart, a series, an axis, and a size each reject an unknown key" {
  let cases = [
    (
      "      - at: D2\n        type: column\n        depth: 3\n        series:\n          - values: B2:B4\n",
      "unknown key 'depth' in chart at 'D2'",
    ),
    (
      "      - at: D2\n        type: column\n        series:\n          - values: B2:B4\n            colour: red\n",
      "unknown key 'colour' in chart at 'D2' series",
    ),
    (
      "      - at: D2\n        type: column\n        y_axis: { step: 5 }\n        series:\n          - values: B2:B4\n",
      "unknown key 'step' in chart at 'D2' 'y_axis'",
    ),
    (
      "      - at: D2\n        type: column\n        size: { width: 520, depth: 4 }\n        series:\n          - values: B2:B4\n",
      "unknown key 'depth' in chart at 'D2' 'size'",
    ),
  ]
  for entry in cases {
    let (body, expected) = entry
    guard schema_message(chart_spec(body)) is Some(message) else {
      fail("expected a diagnostic")
    }
    assert_true(message.has_prefix("spec.yaml: \{expected}"))
  }
}

///|
test "a size must be whole, positive pixels in both directions" {
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        size: { width: 520 }\n        series:\n          - values: B2:B4\n",
      ),
    ),
    Some("spec.yaml: chart at 'D2' 'size' needs both 'width' and 'height'"),
  )
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        size: { width: 0, height: 300 }\n        series:\n          - values: B2:B4\n",
      ),
    ),
    Some(
      "spec.yaml: chart at 'D2' 'size' 'width' must be between 1 and 20000 pixels, not 0",
    ),
  )
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        size: { width: 5.5, height: 300 }\n        series:\n          - values: B2:B4\n",
      ),
    ),
    Some(
      "spec.yaml: chart at 'D2' 'size' 'width' must be a whole number of pixels",
    ),
  )
}

///|
test "an axis that sets nothing, or sets an impossible range, is a diagnostic" {
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        x_axis: {}\n        series:\n          - values: B2:B4\n",
      ),
    ),
    Some(
      "spec.yaml: chart at 'D2' 'x_axis' sets nothing (expected 'title', 'min', or 'max')",
    ),
  )
  assert_eq(
    schema_message(
      chart_spec(
        "      - at: D2\n        type: column\n        y_axis: { min: 10, max: 10 }\n        series:\n          - values: B2:B4\n",
      ),
    ),
    Some("spec.yaml: chart at 'D2' 'y_axis' has 'min' 10 at or above 'max' 10"),
  )
}

///|
test "charts keep their declaration order" {
  let wb = load_ok(
    chart_spec(
      "      - at: D2\n        type: column\n        series:\n          - values: B2:B4\n      - at: D20\n        type: pie\n        series:\n          - values: C2:C4\n",
    ),
  )
  let charts = wb.sheets[0].charts
  assert_eq(charts.length(), 2)
  assert_eq(charts[0].at.to_a1(), "D2")
  assert_eq(charts[1].kind, Pie)
}
