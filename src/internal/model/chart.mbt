///|
/// A chart floating over `at`. `series` is in legend order and non-empty; a pie
/// draws only the first. An unset optional keeps Excel's default.
pub(all) struct Chart {
  at : @units.CellRef
  kind : ChartKind
  series : Array[ChartSeries]
  title : String?
  legend : LegendPosition?
  size : ChartSize?
  x_axis : ChartAxis?
  y_axis : ChartAxis?
} derive(Eq, Debug)

///|
/// The chart kinds a spec may ask for: those plotting a category against a
/// value.
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
} derive(Eq, Debug)

///|
/// One plotted series; either range may name another sheet. Unset `categories`
/// numbers the points, unset `name` leaves "Series 1".
pub(all) struct ChartSeries {
  values : SheetRange
  categories : SheetRange?
  name : SeriesName?
} derive(Eq, Debug)

///|
/// Where a series' name comes from: written out in the spec, or read from a
/// cell — usually the column header above the values, so that renaming the
/// header renames the series.
pub(all) enum SeriesName {
  Literal(String)
  FromCell(sheet~ : String?, at~ : @units.CellRef)
} derive(Eq, Debug)

///|
/// Where the legend sits, or that there is none.
pub(all) enum LegendPosition {
  Bottom
  Top
  Left
  Right
  TopRight
  NoLegend
} derive(Eq, Debug)

///|
/// A chart's size in pixels, as Excel's own "Size" pane gives it.
pub(all) struct ChartSize {
  width : Int32
  height : Int32
} derive(Eq, Debug)

///|
/// One axis of a chart. Every field is optional; an unset one leaves Excel to
/// scale the axis to the data, which is what it does well.
pub(all) struct ChartAxis {
  title : String?
  min : Double?
  max : Double?
} derive(Eq, Debug)
