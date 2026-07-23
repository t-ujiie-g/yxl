///|
/// A cell's value in the minimal model: text, a number, or a boolean. Richer
/// kinds (dates, formulas, error literals) arrive later.
pub(all) enum CellValue {
  Text(String)
  Number(Double)
  Bool(Bool)
} derive(Eq, Debug)

///|
/// A single populated cell: where it sits and what it holds.
pub(all) struct Cell {
  pos : @units.CellRef
  value : CellValue
} derive(Eq, Debug)

///|
/// One worksheet: a name plus the cells written to it, kept in insertion order.
/// Turning this order into the final workbook layout is the emitter's job.
pub(all) struct Sheet {
  name : String
  cells : Array[Cell]
} derive(Eq, Debug)

///|
/// A workbook: an ordered list of sheets. This is the entire input to the
/// emitter seam (`model -> bytes`, ADR-002).
pub(all) struct Workbook {
  sheets : Array[Sheet]
} derive(Eq, Debug)

///|
/// A new, empty workbook.
pub fn Workbook::new() -> Workbook {
  { sheets: [] }
}

///|
/// Append a new empty sheet and return it so cells can be written to it. The
/// returned sheet shares the workbook's storage, so `set` on it is visible in
/// the workbook.
pub fn Workbook::add_sheet(self : Workbook, name : String) -> Sheet {
  let sheet = Sheet::new(name)
  self.sheets.push(sheet)
  sheet
}

///|
/// A new, empty sheet with the given name.
pub fn Sheet::new(name : String) -> Sheet {
  { name, cells: [] }
}

///|
/// Write a value at a cell reference, appending it to the sheet's cells.
pub fn Sheet::set(
  self : Sheet,
  pos : @units.CellRef,
  value : CellValue,
) -> Unit {
  self.cells.push({ pos, value })
}
