///|
/// A group of sparklines, scaled and styled as a unit. `markers` and `weight`
/// apply to lines only; `min`/`max` are whole numbers, as the backend takes;
/// unset colours keep the style's.
pub(all) struct SparklineGroup {
  kind : SparklineKind
  cells : Array[SparklineCell]
  markers : Bool
  high : Bool
  low : Bool
  min : Int32?
  max : Int32?
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
