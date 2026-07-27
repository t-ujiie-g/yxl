// Slicers: the button panel that filters an Excel table. One button per
// distinct value of one table column; clicking filters the table, visibly.

///|
/// A slicer over a declared table. The table is named, not pointed at: table
/// names share one workbook-wide namespace (Excel's own rule), so the name
/// finds it whatever sheet it sits on.
pub(all) struct Slicer {
  /// The cell the slicer panel's top-left corner sits over.
  at : @units.CellRef
  /// The declared `name:` of the table it filters.
  table : String
  /// The table column whose values become the buttons — one of the table's
  /// header cells.
  column : String
  /// The panel's title; `None` leaves Excel showing the column name.
  caption : String?
  /// The panel's size in pixels; `None` keeps the backend default (200×200).
  width : Int?
  height : Int?
  /// Whether the panel shows its header row; `None` keeps Excel's default.
  header : Bool?
} derive(Eq, Debug)

///|
/// Place a slicer on the sheet.
pub fn Sheet::add_slicer(self : Sheet, slicer : Slicer) -> Unit {
  self.slicers.push(slicer)
}
