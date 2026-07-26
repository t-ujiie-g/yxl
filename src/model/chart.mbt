// Charts: a picture of cells that already exist. A chart names the ranges it
// plots and where it sits; Excel draws it, and redraws it whenever those cells
// change — so nothing here is a value, only a reference to one.

///|
/// A chart anchored on a sheet.
pub(all) struct Chart {
  /// The cell the chart's top-left corner sits over. A chart floats above the
  /// grid rather than filling cells, so this only positions it.
  at : @units.CellRef
  kind : ChartKind
  /// What is plotted, in the order the legend lists it. A chart needs at least
  /// one series; a pie or doughnut draws only the first.
  series : Array[ChartSeries]
  title : String?
  /// Where the legend sits, or `NoLegend`; `None` keeps Excel's default.
  legend : LegendPosition?
  /// The chart's size in pixels; `None` keeps the default size.
  size : ChartSize?
  /// The category (horizontal) and value (vertical) axes. `None` leaves both to
  /// Excel, which scales them to the data.
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
/// One plotted series: the values, what to call them, and what to label them
/// along the category axis.
pub(all) struct ChartSeries {
  /// The cells plotted. May name another sheet, since a chart is routinely put
  /// on a sheet of its own.
  values : SheetRange
  /// The labels down the category axis — for a scatter chart, the X values.
  /// `None` numbers the points 1, 2, 3, …
  categories : SheetRange?
  /// What the legend calls this series; `None` leaves Excel's "Series 1".
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
