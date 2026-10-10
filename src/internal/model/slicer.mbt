///|
/// A slicer over a declared table. The table is named, not pointed at: table
/// names share one workbook-wide namespace (Excel's own rule), so the name
/// finds it whatever sheet it sits on.
///
/// `at` is the cell the panel's top-left corner floats over, `table` the
/// declared `name:` it filters, and `column` one of that table's header cells,
/// whose values become the buttons. `caption` unset leaves Excel showing the
/// column name; `width`/`height` are pixels and unset keeps the backend's
/// 200×200; `header` unset keeps Excel's default.
pub(all) struct Slicer {
  at : @units.CellRef
  table : String
  column : String
  caption : String?
  width : Int?
  height : Int?
  header : Bool?
} derive(Eq, Debug)

///|
/// Place a slicer on the sheet.
pub fn Sheet::add_slicer(self : Sheet, slicer : Slicer) -> Unit {
  self.slicers.push(slicer)
}
