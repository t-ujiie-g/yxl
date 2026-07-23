///|
/// A cell's value in the minimal model: text, a number, a boolean, or a
/// date/time. A `Date` is stored as civil components; the emitter renders it to
/// an Excel serial using the workbook's date system. Richer kinds (formulas,
/// error literals) arrive later.
pub(all) enum CellValue {
  Text(String)
  Number(Double)
  Bool(Bool)
  Date(@units.DateTime)
  /// A formula Excel recomputes on open (stored without a leading `=`), with an
  /// optional cached result (a scalar value) shown until then.
  Formula(formula~ : String, cached~ : CellValue?)
} derive(Eq, Debug)

///|
/// A single populated cell: where it sits, what it holds, and an optional Excel
/// number-format code (e.g. `"#,##0.00"`, `"0%"`). `None` means the General
/// format. Equal format codes compile to a single shared style id (ADR-004).
pub(all) struct Cell {
  pos : @units.CellRef
  value : CellValue
  format : String?
} derive(Eq, Debug)

///|
/// One worksheet: a name plus the cells written to it, kept in insertion order.
/// Turning this order into the final workbook layout is the emitter's job.
pub(all) struct Sheet {
  name : String
  cells : Array[Cell]
} derive(Eq, Debug)

///|
/// A workbook: an ordered list of sheets plus the date system that governs how
/// dates serialize. This is the entire input to the emitter seam (`model ->
/// bytes`, ADR-002).
pub(all) struct Workbook {
  sheets : Array[Sheet]
  date_system : @units.DateSystem
} derive(Eq, Debug)

///|
/// A new, empty workbook. Defaults to the 1900 date system.
pub fn Workbook::new(date_system? : @units.DateSystem = Date1900) -> Workbook {
  { sheets: [], date_system }
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
/// Write a value at a cell reference, appending it to the sheet's cells. Pass
/// `format=` to attach a number-format code.
pub fn Sheet::set(
  self : Sheet,
  pos : @units.CellRef,
  value : CellValue,
  format? : String,
) -> Unit {
  self.cells.push({ pos, value, format })
}
