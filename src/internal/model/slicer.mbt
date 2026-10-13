///|
/// A slicer over a declared table, found by name in the workbook-wide table
/// namespace; `column` is one of its headers. `None` keeps Excel's or the
/// backend's default.
pub(all) struct Slicer {
  at : @units.CellRef
  table : String
  column : String
  caption : String?
  width : Int32?
  height : Int32?
  header : Bool?
} derive(Eq, Debug)

///|
/// Place a slicer on the sheet.
pub fn Sheet::add_slicer(self : Sheet, slicer : Slicer) -> Unit {
  self.slicers.push(slicer)
}
