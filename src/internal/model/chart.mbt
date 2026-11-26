///|
/// A chart floating over `at`. `series` is in legend order and non-empty; a pie
/// draws only the first. An unset optional keeps Excel's default.
#derive(Eq, Debug)
pub(all) struct Chart {
  at : @units.CellRef
  kind : ChartKind
  series : Array[ChartSeries]
  title : String?
  legend : LegendPosition?
  size : ChartSize?
  x_axis : ChartAxis?
  y_axis : ChartAxis?
}

///|
/// The chart kinds a spec may ask for: those plotting a category against a
/// value.
#derive(Eq, Debug)
pub(all) enum ChartKind {
  Column
  ColumnStacked
  ColumnPercentStacked
  Bar
  BarStacked
  BarPercentStacked
  Line
  Area
  AreaStacked
  AreaPercentStacked
  Pie
  Doughnut
  Scatter
  Radar
}

///|
/// One plotted series; either range may name another sheet. Unset `categories`
/// numbers the points, unset `name` leaves "Series 1".
#derive(Eq, Debug)
pub(all) struct ChartSeries {
  values : SheetRange
  categories : SheetRange?
  name : SeriesName?
}

///|
/// Where a series' name comes from: written out in the spec, or read from a
/// cell — usually the column header above the values, so that renaming the
/// header renames the series.
#derive(Eq, Debug)
pub(all) enum SeriesName {
  Literal(String)
  FromCell(sheet~ : String?, at~ : @units.CellRef)
}

///|
/// Where the legend sits, or that there is none.
#derive(Eq, Debug)
pub(all) enum LegendPosition {
  Bottom
  Top
  Left
  Right
  TopRight
  NoLegend
}

///|
/// A chart's size in pixels, as Excel's own "Size" pane gives it.
#derive(Eq, Debug)
pub(all) struct ChartSize {
  width : Int32
  height : Int32
}

///|
/// One axis of a chart. Every field is optional; an unset one leaves Excel to
/// scale the axis to the data, which is what it does well.
#derive(Eq, Debug)
pub(all) struct ChartAxis {
  title : String?
  min : Double?
  max : Double?
}

///|
/// The chart kinds a spec may name. The loader reads them from here and
/// `yxl extract` spells them from here, so the two cannot drift apart.
pub let chart_kinds : Array[(String, ChartKind)] = [
  ("column", Column),
  ("column_stacked", ColumnStacked),
  ("column_percent_stacked", ColumnPercentStacked),
  ("bar", Bar),
  ("bar_stacked", BarStacked),
  ("bar_percent_stacked", BarPercentStacked),
  ("line", Line),
  ("area", Area),
  ("area_stacked", AreaStacked),
  ("area_percent_stacked", AreaPercentStacked),
  ("pie", Pie),
  ("doughnut", Doughnut),
  ("scatter", Scatter),
  ("radar", Radar),
]

///|
/// Where a legend may sit. `none` leaves the chart without one.
pub let legend_positions : Array[(String, LegendPosition)] = [
  ("bottom", Bottom),
  ("top", Top),
  ("left", Left),
  ("right", Right),
  ("top_right", TopRight),
  ("none", NoLegend),
]
