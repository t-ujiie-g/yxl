///|
/// The range `TopLeft:BottomRight`, both corners given in A1.
fn range(top_left : String, bottom_right : String) -> @model.CellRange {
  { top_left: at(top_left), bottom_right: at(bottom_right) }
}

///|
/// A workbook whose one sheet carries `chart` over a small block of figures.
fn with_chart(chart : @model.Chart) -> @model.Workbook {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.set(at("B1"), Text("Revenue"))
  sheet.set(at("A2"), Text("APAC"))
  sheet.set(at("B2"), Number(24.0))
  sheet.set(at("A3"), Text("EMEA"))
  sheet.set(at("B3"), Number(17.0))
  sheet.add_chart(chart)
  wb
}

///|
/// The plainest chart there is, with `kind` swapped in.
fn plain_chart(kind : @model.ChartKind) -> @model.Chart {
  {
    at: at("D2"),
    kind,
    series: [
      {
        values: { sheet: None, range: range("B2", "B3") },
        categories: Some({ sheet: None, range: range("A2", "A3") }),
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
/// The sole chart of a round-tripped workbook.
fn only_chart(wb : @model.Workbook) -> @model.Chart raise {
  let sheet = only_sheet(wb)
  assert_eq(sheet.charts.length(), 1)
  sheet.charts[0]
}

///|
test "every kind the schema names comes back as itself" {
  // The point of the sweep: `barDir` and `grouping` together decide six of
  // these, and reading either one wrongly gives a chart that plots the same
  // numbers a different way — which no round-trip of the *ranges* would catch.
  let kinds : Array[@model.ChartKind] = [
    Column,
    ColumnStacked,
    ColumnPercentStacked,
    Bar,
    BarStacked,
    BarPercentStacked,
    Line,
    Area,
    AreaStacked,
    AreaPercentStacked,
    Pie,
    Doughnut,
    Scatter,
    Radar,
  ]
  for kind in kinds {
    let recovered = only_chart(with_chart(plain_chart(kind)))
    assert_eq(recovered.kind, kind)
  }
}

///|
test "a chart round-trips its anchor, ranges, title, legend, size, and axes" {
  let chart : @model.Chart = {
    ..plain_chart(Column),
    title: Some("Revenue by region"),
    legend: Some(Bottom),
    size: Some({ width: 520, height: 300 }),
    x_axis: Some({ title: Some("Region"), min: None, max: None }),
    y_axis: Some({ title: Some("Amount"), min: Some(0.0), max: Some(40.0) }),
    series: [
      {
        values: { sheet: None, range: range("B2", "B3") },
        categories: Some({ sheet: None, range: range("A2", "A3") }),
        name: Some(FromCell(sheet=None, at=at("B1"))),
      },
    ],
  }
  let recovered = only_chart(with_chart(chart))
  assert_eq(recovered.at, at("D2"))
  assert_eq(recovered.title, Some("Revenue by region"))
  assert_eq(recovered.legend, Some(Bottom))
  assert_eq(recovered.size, Some({ width: 520, height: 300 }))
  assert_eq(
    recovered.x_axis,
    Some({ title: Some("Region"), min: None, max: None }),
  )
  assert_eq(
    recovered.y_axis,
    Some({ title: Some("Amount"), min: Some(0.0), max: Some(40.0) }),
  )
  // Every range comes back sheet-qualified, because that is how the file stores
  // one: a chart lives in a part of its own, where a bare `B2:B3` names nothing.
  assert_eq(recovered.series.length(), 1)
  assert_eq(recovered.series[0].values, {
    sheet: Some("S"),
    range: range("B2", "B3"),
  })
  assert_eq(
    recovered.series[0].categories,
    Some({ sheet: Some("S"), range: range("A2", "A3") }),
  )
  assert_eq(
    recovered.series[0].name,
    Some(FromCell(sheet=Some("S"), at=at("B1"))),
  )
}

///|
test "a series named outright keeps its words" {
  let chart : @model.Chart = {
    ..plain_chart(Pie),
    series: [
      {
        values: { sheet: None, range: range("B2", "B3") },
        categories: Some({ sheet: None, range: range("A2", "A3") }),
        name: Some(Literal("Revenue")),
      },
    ],
  }
  let recovered = only_chart(with_chart(chart))
  assert_eq(recovered.series[0].name, Some(Literal("Revenue")))
}

///|
test "a chart with no legend comes back saying so" {
  // `none` and "unset" are different specs — one draws no legend, the other
  // takes Excel's default — so the absent `<c:legend>` has to mean the first.
  let recovered = only_chart(
    with_chart({ ..plain_chart(Column), legend: Some(NoLegend) }),
  )
  assert_eq(recovered.legend, Some(NoLegend))
}

///|
test "a chart at the backend's own size says nothing about it" {
  // Writing the default back would put a `size:` on every extracted chart that
  // never asked for one.
  let recovered = only_chart(with_chart(plain_chart(Column)))
  assert_eq(recovered.size, None)
}

///|
test "a scatter chart's X range is its categories" {
  // Scatter spells its two ranges `xVal`/`yVal` rather than `cat`/`val`, so
  // reading it by the other pair would lose both.
  let recovered = only_chart(with_chart(plain_chart(Scatter)))
  assert_eq(recovered.series[0].values.range, range("B2", "B3"))
  assert_eq(
    recovered.series[0].categories.map(source => source.range),
    Some(range("A2", "A3")),
  )
}

///|
/// A workbook whose one sheet carries a chart with exactly this part.
fn foreign_chart(xml : String) -> @read.Recovered raise {
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("S")
  backend.set_cell_str("S", "A1", "Region")
  backend.set_cell_int("S", "B1", 1)
  guard backend.sheet("S") is Some(source) else { fail("missing sheet") }
  source.add_chart("D2", xml)
  @read.from_bytes(backend.write_to_buffer())
}

///|
/// A `chartSpace` around whatever the plot area should hold.
fn chart_part(plot_area : String, extra? : String = "") -> String {
  (
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><c:chart>
  ) +
  extra +
  "<c:plotArea><c:layout/>" +
  plot_area +
  "</c:plotArea></c:chart></c:chartSpace>"
}

///|
/// One series over `S!$B$2:$B$3`, spelled the way a file spells one.
fn part_series() -> String {
  (
    #|<c:ser><c:idx val="0"/><c:val><c:numRef><c:f>'S'!$B$2:$B$3</c:f></c:numRef></c:val></c:ser>
  )
}

///|
/// Whether any loss note contains `fragment`.
fn reported(recovered : @read.Recovered, fragment : String) -> Bool {
  recovered.dropped.iter().any(note => note.contains(fragment))
}

///|
test "a combination chart is refused rather than read as its first half" {
  // Bars with a line over them. Reading the first group would produce a spec
  // that compiles to a chart missing a series and saying nothing about it.
  let recovered = foreign_chart(
    chart_part(
      "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" +
      part_series() +
      "</c:barChart><c:lineChart><c:grouping val=\"standard\"/>" +
      part_series() +
      "</c:lineChart>",
    ),
  )
  assert_eq(recovered.workbook.sheets[0].charts, [])
  assert_true(reported(recovered, "combines 2 chart types in one plot area"))
}

///|
test "a stacked line chart is refused rather than called a line chart" {
  // The schema has `line` and no stacked variant of it. "Line" would plot the
  // same ranges a different way, which is the wrong answer this reader exists
  // to avoid.
  let recovered = foreign_chart(
    chart_part(
      "<c:lineChart><c:grouping val=\"stacked\"/>" +
      part_series() +
      "</c:lineChart>",
    ),
  )
  assert_eq(recovered.workbook.sheets[0].charts, [])
  assert_true(reported(recovered, "which is a 'lineChart'"))
}

///|
test "a chart kind the schema has no word for is refused by name" {
  let recovered = foreign_chart(
    chart_part("<c:bubbleChart>" + part_series() + "</c:bubbleChart>"),
  )
  assert_eq(recovered.workbook.sheets[0].charts, [])
  assert_true(reported(recovered, "which is a 'bubbleChart'"))
}

///|
test "a title read from a cell is reported, and the chart keeps the rest" {
  // The spec carries a title as text, so recovering the reference would put
  // `'S'!$A$1` on the chart as literal words.
  let recovered = foreign_chart(
    chart_part(
      "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" +
      part_series() +
      "</c:barChart>",
      extra="<c:title><c:tx><c:strRef><c:f>'S'!$A$1</c:f></c:strRef></c:tx></c:title>",
    ),
  )
  let charts = recovered.workbook.sheets[0].charts
  assert_eq(charts.length(), 1)
  assert_eq(charts[0].title, None)
  assert_true(reported(recovered, "whose title is read from"))
}

///|
test "a series holding its values outright is refused" {
  // `c:numLit` is a series with the numbers written into the chart part rather
  // than pointing at cells. A spec has no way to say that.
  let recovered = foreign_chart(
    chart_part(
      "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" +
      "<c:ser><c:idx val=\"0\"/><c:val><c:numLit><c:ptCount val=\"1\"/>" +
      "<c:pt idx=\"0\"><c:v>3</c:v></c:pt></c:numLit></c:val></c:ser>" +
      "</c:barChart>",
    ),
  )
  assert_eq(recovered.workbook.sheets[0].charts, [])
  assert_true(reported(recovered, "holds its values outright"))
}

///|
test "a chart with no series at all is refused" {
  let recovered = foreign_chart(
    chart_part("<c:barChart><c:barDir val=\"col\"/></c:barChart>"),
  )
  assert_eq(recovered.workbook.sheets[0].charts, [])
  assert_true(reported(recovered, "which plots no series"))
}

///|
test "a part that is not a chart is refused rather than half-read" {
  let recovered = foreign_chart(
    (
      #|<?xml version="1.0" encoding="UTF-8"?>
      #|<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:lang val="en-US"/></c:chartSpace>
    ),
  )
  assert_eq(recovered.workbook.sheets[0].charts, [])
  assert_true(reported(recovered, "not a chart this reader can follow"))
}

///|
test "a series name spanning more than one cell is dropped, not guessed at" {
  let recovered = foreign_chart(
    chart_part(
      "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" +
      "<c:ser><c:idx val=\"0\"/>" +
      "<c:tx><c:strRef><c:f>'S'!$A$1:$B$1</c:f></c:strRef></c:tx>" +
      "<c:val><c:numRef><c:f>'S'!$B$2:$B$3</c:f></c:numRef></c:val>" +
      "</c:ser></c:barChart>",
    ),
  )
  let charts = recovered.workbook.sheets[0].charts
  assert_eq(charts.length(), 1)
  assert_eq(charts[0].series[0].name, None)
  assert_true(reported(recovered, "which is a range rather than a cell"))
}

///|
test "a data label's own reference is not mistaken for the series' name" {
  // Both are `c:tx`. Only nesting tells them apart, and a scan that took the
  // first one it met would name every series after its data labels.
  let recovered = foreign_chart(
    chart_part(
      "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" +
      "<c:ser><c:idx val=\"0\"/>" +
      "<c:tx><c:strRef><c:f>'S'!$B$1</c:f></c:strRef></c:tx>" +
      "<c:dLbls><c:tx><c:strRef><c:f>'S'!$A$1</c:f></c:strRef></c:tx></c:dLbls>" +
      "<c:val><c:numRef><c:f>'S'!$B$2:$B$3</c:f></c:numRef></c:val>" +
      "</c:ser></c:barChart>",
    ),
  )
  let charts = recovered.workbook.sheets[0].charts
  assert_eq(charts.length(), 1)
  assert_eq(
    charts[0].series[0].name,
    Some(FromCell(sheet=Some("S"), at=at("B1"))),
  )
}

///|
test "an axis is matched to its group by id, not by where it sits" {
  // A chart with a secondary axis has four, and the group names the two that
  // are its own. Reading them positionally would take the wrong pair.
  let recovered = foreign_chart(
    chart_part(
      "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" +
      part_series() +
      "<c:axId val=\"77\"/><c:axId val=\"88\"/></c:barChart>" +
      "<c:valAx><c:axId val=\"99\"/><c:scaling><c:max val=\"1000\"/></c:scaling></c:valAx>" +
      "<c:catAx><c:axId val=\"77\"/><c:title><c:tx><c:rich><a:p><a:r><a:t>Region</a:t></a:r></a:p></c:rich></c:tx></c:title></c:catAx>" +
      "<c:valAx><c:axId val=\"88\"/><c:scaling><c:min val=\"0\"/></c:scaling></c:valAx>",
    ),
  )
  let charts = recovered.workbook.sheets[0].charts
  assert_eq(charts.length(), 1)
  assert_eq(
    charts[0].x_axis,
    Some({ title: Some("Region"), min: None, max: None }),
  )
  assert_eq(charts[0].y_axis, Some({ title: None, min: Some(0.0), max: None }))
}

///|
test "an axis that says nothing the spec can carry is left out entirely" {
  // `x_axis: {}` is a mapping the loader refuses — the schema wants at least
  // one of title, min and max — so an axis with none of them must not appear.
  let recovered = foreign_chart(
    chart_part(
      "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" +
      part_series() +
      "<c:axId val=\"1\"/><c:axId val=\"2\"/></c:barChart>" +
      "<c:catAx><c:axId val=\"1\"/><c:delete val=\"0\"/></c:catAx>" +
      "<c:valAx><c:axId val=\"2\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling></c:valAx>",
    ),
  )
  let charts = recovered.workbook.sheets[0].charts
  assert_eq(charts.length(), 1)
  assert_eq(charts[0].x_axis, None)
  assert_eq(charts[0].y_axis, None)
}

///|
test "a title split across runs is one title" {
  // Excel starts a new run wherever the formatting changes, so a title with one
  // bold word arrives in three pieces.
  let recovered = foreign_chart(
    chart_part(
      "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/>" +
      part_series() +
      "</c:barChart>",
      extra="<c:title><c:tx><c:rich><a:p><a:r><a:t>Revenue </a:t></a:r>" +
        "<a:r><a:rPr b=\"1\"/><a:t>by</a:t></a:r>" +
        "<a:r><a:t> region</a:t></a:r></a:p></c:rich></c:tx></c:title>",
    ),
  )
  let charts = recovered.workbook.sheets[0].charts
  assert_eq(charts.length(), 1)
  assert_eq(charts[0].title, Some("Revenue by region"))
}
