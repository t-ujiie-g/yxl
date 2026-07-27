// Sparklines: a chart inside one cell, for a row of figures beside it. They
// come in *groups* — every cell in a group shares the kind, the look, and any
// manual bounds, which is what makes a column of them read as one series.

///|
/// A group of sparklines. Excel scales and styles a group as a unit.
pub(all) struct SparklineGroup {
  kind : SparklineKind
  /// Where each sparkline lands and what it plots; at least one.
  cells : Array[SparklineCell]
  /// Dot every point (line kind only — the others already draw one mark per
  /// point).
  markers : Bool
  /// Emphasize the highest and lowest points.
  high : Bool
  low : Bool
  /// Manual vertical bounds; `None` lets Excel scale each axis end to the
  /// data. Whole numbers because the backend accepts nothing finer.
  min : Int?
  max : Int?
  /// The line weight in points (line kind only); `None` keeps Excel's.
  weight : Double?
  /// The series colour, and the marker colours; `None` keeps the style's.
  color : @units.Color?
  markers_color : @units.Color?
  high_color : @units.Color?
  low_color : @units.Color?
  /// Draw the horizontal axis at zero.
  axis : Bool
} derive(Eq, Debug)

///|
/// One sparkline of a group: the cell it sits in, and the cells it plots —
/// possibly on another sheet.
pub(all) struct SparklineCell {
  at : @units.CellRef
  data : SheetRange
} derive(Eq, Debug)

///|
/// The three shapes Excel draws in a cell (ECMA-376 Part 4 §2.9, `x14`):
/// a line, a column per point, or win/loss — every point the same size,
/// above or below the axis by its sign.
pub(all) enum SparklineKind {
  Line
  Column
  WinLoss
} derive(Eq, Debug)

///|
/// Place a sparkline group on the sheet.
pub fn Sheet::add_sparkline_group(self : Sheet, group : SparklineGroup) -> Unit {
  self.sparklines.push(group)
}
