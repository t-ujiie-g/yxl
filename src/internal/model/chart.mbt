///|
/// A chart anchored on a sheet: `at` is the cell its top-left corner floats
/// over, since a chart sits above the grid rather than filling cells. `series`
/// is in the order the legend lists it, and needs at least one entry — a pie or
/// doughnut draws only the first. `x_axis` is the category (horizontal) axis
/// and `y_axis` the value (vertical) one.
///
/// Every optional field left `None` keeps Excel's own default.
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
/// The kinds of chart a spec may ask for — the ones that plot a category
/// against a value, which is what a spreadsheet's cells usually hold.
///
/// Excel's 3-D variants, stock charts, and bubble charts are not here: each
/// wants either an extra range per series or a shape the spec has no way to
/// describe yet.
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
/// One plotted series: the cells plotted, what the legend calls them, and what
/// labels them along the category axis — for a scatter chart, the X values.
/// Either range may name another sheet, since a chart is routinely put on a
/// sheet of its own.
///
/// `categories` unset numbers the points 1, 2, 3, …; `name` unset leaves
/// Excel's "Series 1".
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
  width : Int
  height : Int
} derive(Eq, Debug)

///|
/// One axis of a chart. Every field is optional; an unset one leaves Excel to
/// scale the axis to the data, which is what it does well.
pub(all) struct ChartAxis {
  title : String?
  min : Double?
  max : Double?
} derive(Eq, Debug)
