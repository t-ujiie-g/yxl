// Emitting charts. Every range a chart plots is written the way Excel writes
// one itself — sheet-qualified and absolute — because a chart lives in a part of
// its own, where a bare `B2:B4` names nothing.

///|
/// Anchor a chart on a sheet: its kind and series, then the trimmings that were
/// asked for. Anything the spec left out keeps the backend's default rather than
/// being written as an explicit "unset".
fn apply_chart(
  backend : @xlsx.Workbook,
  sheet_name : String,
  chart : @model.Chart,
) -> Unit raise {
  let options = @xlsx.ChartOptions::new(chart_type(chart.kind))
  for series in chart.series {
    options.series.push(build_series(series, sheet_name))
  }
  if chart.title is Some(title) {
    options.title = title
  }
  if chart.legend is Some(position) {
    options.legend.position = legend_position(position)
  }
  if chart.size is Some(size) {
    options.dimension = @xlsx.ChartDimension::with_values(
      size.width,
      size.height,
    )
  }
  if chart.x_axis is Some(axis) {
    apply_axis(options.x_axis, axis)
  }
  if chart.y_axis is Some(axis) {
    apply_axis(options.y_axis, axis)
  }
  backend.add_chart_with_options(sheet_name, chart.at.to_a1(), options)
}

///|
/// One series, with every range resolved against the sheet the chart sits on.
fn build_series(
  series : @model.ChartSeries,
  sheet_name : String,
) -> @xlsx.ChartSeries raise {
  let values = qualified_range(series.values, sheet_name)
  // Excel numbers the points itself when no categories are given, and the
  // backend spells that as an empty string.
  let categories = match series.categories {
    Some(range) => qualified_range(range, sheet_name)
    None => ""
  }
  let name = match series.name {
    // A name holding '!' is read by the backend as a reference to a cell, which
    // is exactly what `FromCell` asks for; the loader keeps a literal one from
    // ever containing it.
    Some(Literal(text)) => text
    Some(FromCell(sheet~, at~)) =>
      quoted_sheet(sheet.unwrap_or(sheet_name)) + "!" + at.to_absolute_a1()
    None => ""
  }
  @xlsx.ChartSeries::new(categories, values, name~)
}

///|
/// A range as a chart names one: `'Sales'!$A$2:$A$4`, on the chart's own sheet
/// unless the spec named another.
fn qualified_range(range : @model.SheetRange, sheet_name : String) -> String {
  absolute_range(range.sheet.unwrap_or(sheet_name), range.range)
}

///|
/// What the spec asked of an axis, over the backend's defaults. An unset field
/// is left alone, so Excel keeps scaling that end to the data.
fn apply_axis(backend : @xlsx.ChartAxis, axis : @model.ChartAxis) -> Unit {
  if axis.title is Some(title) {
    backend.title = title
  }
  if axis.min is Some(min) {
    backend.minimum = Some(min)
  }
  if axis.max is Some(max) {
    backend.maximum = Some(max)
  }
}

///|
/// The backend's chart type for a model kind.
fn chart_type(kind : @model.ChartKind) -> @xlsx.ChartType {
  match kind {
    Column => Col
    ColumnStacked => ColStacked
    ColumnPercentStacked => ColPercentStacked
    Bar => Bar
    BarStacked => BarStacked
    BarPercentStacked => BarPercentStacked
    Line => Line
    Area => Area
    AreaStacked => AreaStacked
    AreaPercentStacked => AreaPercentStacked
    Pie => Pie
    Doughnut => Doughnut
    Scatter => Scatter
    Radar => Radar
  }
}

///|
/// The backend's legend position, which it spells as one of Excel's own words —
/// and as `"none"` for a chart without a legend.
fn legend_position(position : @model.LegendPosition) -> String {
  match position {
    Bottom => "bottom"
    Top => "top"
    Left => "left"
    Right => "right"
    TopRight => "top_right"
    NoLegend => "none"
  }
}
