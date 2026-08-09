///|
/// The sole chart the round-tripped workbook carries, as its anchor, its size in
/// EMU, and its XML.
fn only_chart(wb : @model.Workbook) -> @xlsx.Chart raise {
  let reopened = reopen(wb)
  guard reopened.sheet("S") is Some(sheet) else { fail("expected the sheet") }
  let charts = sheet.charts()
  assert_eq(charts.length(), 1)
  charts[0]
}

///|
/// A chart of one series over `B2:B4`, labelled from `A2:A4`.
fn one_series(kind : @model.ChartKind) -> @model.Chart {
  {
    at: @units.CellRef::parse_a1("D2").unwrap(),
    kind,
    series: [
      {
        values: { sheet: None, range: range("B2", "B4") },
        categories: Some({ sheet: None, range: range("A2", "A4") }),
        name: None,
      },
    ],
    title: None,
    legend: None,
    size: None,
    x_axis: None,
    y_axis: None,
  }
}

///|
test "a chart round-trips as its anchor, its plot, and its ranges" {
  let (wb, sheet) = fixture()
  sheet.add_chart(one_series(Column))
  let chart = only_chart(wb)
  assert_eq(chart.reference, "D2")
  assert_true(chart.xml.contains("<c:barChart>"))
  assert_true(chart.xml.contains("<c:barDir val=\"col\"/>"))
  // Every range is sheet-qualified and absolute: a chart lives in a part of its
  // own, where a bare `B2:B4` names nothing.
  assert_true(chart.xml.contains("<c:f>'S'!$B$2:$B$4</c:f>"))
  assert_true(chart.xml.contains("<c:f>'S'!$A$2:$A$4</c:f>"))
}

///|
test "each chart kind reaches the file as its own plot" {
  let expected : Array[(@model.ChartKind, String)] = [
    (Column, "<c:barChart>"),
    (Bar, "<c:barChart>"),
    (Line, "<c:lineChart>"),
    (Area, "<c:areaChart>"),
    (Pie, "<c:pieChart>"),
    (Doughnut, "<c:doughnutChart>"),
    (Scatter, "<c:scatterChart>"),
    (Radar, "<c:radarChart>"),
  ]
  for entry in expected {
    let (kind, plot) = entry
    let (wb, sheet) = fixture()
    sheet.add_chart(one_series(kind))
    assert_true(only_chart(wb).xml.contains(plot))
  }
}

///|
test "a stacked kind keeps its grouping, not just its plot" {
  for
    entry in [
      (@model.ChartKind::Column, "clustered"),
      (ColumnStacked, "stacked"),
      (ColumnPercentStacked, "percentStacked"),
    ] {
    let (kind, grouping) = entry
    let (wb, sheet) = fixture()
    sheet.add_chart(one_series(kind))
    assert_true(
      only_chart(wb).xml.contains("<c:grouping val=\"\{grouping}\"/>"),
    )
  }
}

///|
test "a series is named either outright or from a cell" {
  let (wb, sheet) = fixture()
  let chart = one_series(Column)
  sheet.add_chart({
    ..chart,
    series: [
      { ..chart.series[0], name: Some(Literal("Revenue")) },
      {
        ..chart.series[0],
        name: Some(
          FromCell(sheet=None, at=@units.CellRef::parse_a1("C1").unwrap()),
        ),
      },
    ],
  })
  let xml = only_chart(wb).xml
  assert_true(xml.contains("<c:tx><c:v>Revenue</c:v></c:tx>"))
  assert_true(
    xml.contains("<c:tx><c:strRef><c:f>'S'!$C$1</c:f></c:strRef></c:tx>"),
  )
}

///|
test "a series may plot another sheet" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  wb.add_sheet("Data") |> ignore
  let chart = one_series(Column)
  sheet.add_chart({
    ..chart,
    series: [
      {
        values: { sheet: Some("Data"), range: range("B2", "B4") },
        categories: Some({ sheet: Some("Data"), range: range("A2", "A4") }),
        name: None,
      },
    ],
  })
  let xml = only_chart(wb).xml
  assert_true(xml.contains("<c:f>'Data'!$B$2:$B$4</c:f>"))
  assert_true(xml.contains("<c:f>'Data'!$A$2:$A$4</c:f>"))
}

///|
test "the title, legend, and axes reach the file" {
  let (wb, sheet) = fixture()
  sheet.add_chart({
    ..one_series(Column),
    title: Some("Revenue by region"),
    legend: Some(Right),
    x_axis: Some({ title: Some("Region"), min: None, max: None }),
    y_axis: Some({ title: None, min: Some(0.0), max: Some(4000000.0) }),
  })
  let xml = only_chart(wb).xml
  assert_true(xml.contains("<a:t>Revenue by region</a:t>"))
  assert_true(xml.contains("<a:t>Region</a:t>"))
  assert_true(xml.contains("<c:legendPos val=\"r\"/>"))
  assert_true(xml.contains("<c:min val=\"0\"/>"))
  assert_true(xml.contains("<c:max val=\"4000000\"/>"))
}

///|
test "a chart without a legend has none, rather than an empty one" {
  let (wb, sheet) = fixture()
  sheet.add_chart({ ..one_series(Column), legend: Some(NoLegend) })
  assert_false(only_chart(wb).xml.contains("<c:legend>"))
}

///|
test "a size in pixels reaches the file in EMU" {
  let (wb, sheet) = fixture()
  sheet.add_chart({
    ..one_series(Column),
    size: Some({ width: 520, height: 300 }),
  })
  let chart = only_chart(wb)
  // One pixel is 9525 EMU (ECMA-376 §20.1.2.1: 914400 EMU per inch, at 96 dpi).
  assert_eq(chart.width_emu, 520 * 9525)
  assert_eq(chart.height_emu, 300 * 9525)
}

///|
test "two charts on one sheet keep their own anchors" {
  let (wb, sheet) = fixture()
  sheet.add_chart(one_series(Column))
  sheet.add_chart({
    ..one_series(Line),
    at: @units.CellRef::parse_a1("D20").unwrap(),
  })
  let reopened = reopen(wb)
  guard reopened.sheet("S") is Some(read) else { fail("expected the sheet") }
  let charts = read.charts()
  assert_eq(charts.length(), 2)
  assert_eq(charts[0].reference, "D2")
  assert_eq(charts[1].reference, "D20")
  assert_true(charts[1].xml.contains("<c:lineChart>"))
}
