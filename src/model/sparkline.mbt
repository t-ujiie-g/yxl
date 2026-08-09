///|
/// A group of sparklines. Excel scales and styles a group as a unit.
///
/// - `cells` — where each sparkline lands and what it plots; at least one.
/// - `markers`, `weight` — dot every point, and the line weight in points. Both
///   belong to the line kind: the others already draw one mark per point.
/// - `high`, `low`, `axis` — emphasize the extremes, and draw the horizontal
///   axis at zero.
/// - `min`, `max` — manual vertical bounds; unset lets Excel scale each end to
///   the data. Whole numbers, because the backend accepts nothing finer.
/// - the colours — unset keeps the style's.
pub(all) struct SparklineGroup {
  kind : SparklineKind
  cells : Array[SparklineCell]
  markers : Bool
  high : Bool
  low : Bool
  min : Int?
  max : Int?
  weight : Double?
  color : @units.Color?
  markers_color : @units.Color?
  high_color : @units.Color?
  low_color : @units.Color?
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
