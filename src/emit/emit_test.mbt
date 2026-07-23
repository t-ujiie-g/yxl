///|
/// Golden / round-trip test at the compile boundary: a model compiles to `.xlsx`
/// bytes, and re-opening those bytes with the backend's reader yields the cells
/// the model declared.
test "to_bytes round-trips a model through real .xlsx bytes" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("Sheet1")
  sheet.set(@units.CellRef::new(col=1, row=1), Text("yxl"))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(42.0))
  sheet.set(@units.CellRef::new(col=3, row=1), Bool(true))
  sheet.set(@units.CellRef::new(col=1, row=2), Text("second row"))
  let bytes = @emit.to_bytes(wb)

  // A valid .xlsx is a non-empty ZIP: check the local-file-header magic.
  assert_true(bytes.length() > 0)
  assert_eq(bytes[0], b'P')
  assert_eq(bytes[1], b'K')

  // Re-open and confirm the declared cells survived the round trip.
  let reopened = @xlsx.read(bytes[:])
  assert_eq(reopened.get_cell("Sheet1", "A1"), Some("yxl"))
  assert_eq(reopened.get_cell("Sheet1", "B1"), Some("42"))
  // The backend reads a boolean cell back as "1"/"0".
  assert_eq(reopened.get_cell("Sheet1", "C1"), Some("1"))
  assert_eq(reopened.get_cell("Sheet1", "A2"), Some("second row"))
}

///|
test "MbtexcelEmitter emits every sheet in order" {
  let wb = @model.Workbook::new()
  wb.add_sheet("First").set(@units.CellRef::new(col=1, row=1), Text("a"))
  wb.add_sheet("Second").set(@units.CellRef::new(col=1, row=1), Text("b"))
  let bytes = @emit.MbtexcelEmitter::new().emit(wb)
  let reopened = @xlsx.read(bytes[:])
  assert_eq(reopened.get_cell("First", "A1"), Some("a"))
  assert_eq(reopened.get_cell("Second", "A1"), Some("b"))
}

///|
test "number formats are applied, and equal formats share one style id" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  sheet.set(@units.CellRef::new(col=1, row=1), Number(0.5), format="0.00%")
  sheet.set(@units.CellRef::new(col=2, row=1), Number(0.25), format="0.00%")
  sheet.set(
    @units.CellRef::new(col=3, row=1),
    Number(1234.5),
    format="#,##0.00",
  )
  sheet.set(@units.CellRef::new(col=4, row=1), Number(7.0))
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])

  // The format is really applied: the formatted read-back reflects it.
  assert_eq(reopened.get_cell_value("S", "A1", raw=false), Some("50.00%"))
  assert_eq(reopened.get_cell_value("S", "C1", raw=false), Some("1,234.50"))

  // Interning (ADR-004): equal format codes compile to one shared style id,
  // distinct codes to distinct ids, and an unformatted cell to the default.
  let percent = reopened.get_cell_style("S", "A1")
  assert_eq(reopened.get_cell_style("S", "B1"), percent)
  assert_not_eq(reopened.get_cell_style("S", "C1"), percent)
  assert_eq(reopened.get_cell_style("S", "D1"), Some(0))
}

///|
test "a date cell serializes to its Excel serial under the workbook's system" {
  let date = @units.DateTime::{
    year: 1900,
    month: 1,
    day: 1,
    hour: 0,
    minute: 0,
    second: 0,
  }
  // 1900 system: 1900-01-01 is serial 1.
  let wb1900 = @model.Workbook::new()
  wb1900.add_sheet("S").set(@units.CellRef::new(col=1, row=1), Date(date))
  let r1900 = @xlsx.read(@emit.to_bytes(wb1900)[:])
  assert_eq(r1900.get_cell_value("S", "A1", raw=true), Some("1"))

  // 1904 system: 1900-01-01 is 1460 real days before the 1904 epoch. (The
  // familiar "1462" offset between the systems only holds after Feb 1900, once
  // the 1900 leap-year bug applies.) The backend computes the same serial.
  let wb1904 = @model.Workbook::new(date_system=Date1904)
  wb1904.add_sheet("S").set(@units.CellRef::new(col=1, row=1), Date(date))
  let r1904 = @xlsx.read(@emit.to_bytes(wb1904)[:])
  assert_eq(r1904.get_cell_value("S", "A1", raw=true), Some("-1460"))
}

///|
test "a formula cell emits its formula and optional cached value" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  sheet.set(@units.CellRef::new(col=1, row=1), Number(3.0))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(4.0))
  // A1+B1 with a cached result of 7.
  sheet.set(
    @units.CellRef::new(col=3, row=1),
    Formula(formula="A1+B1", cached=Some(Number(7.0))),
  )
  // A formula without a cached value.
  sheet.set(
    @units.CellRef::new(col=4, row=1),
    Formula(formula="A1*B1", cached=None),
  )
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  assert_eq(reopened.get_cell_formula("S", "C1"), Some("A1+B1"))
  assert_eq(reopened.get_cell_formula("S", "D1"), Some("A1*B1"))
  // The cached value is stored and read back raw.
  assert_eq(reopened.get_cell_value("S", "C1", raw=true), Some("7"))
}

///|
test "an error literal round-trips as the error text" {
  let wb = @model.Workbook::new()
  wb.add_sheet("S").set(@units.CellRef::new(col=1, row=1), Error("#DIV/0!"))
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  assert_eq(reopened.get_cell_value("S", "A1", raw=true), Some("#DIV/0!"))
}

///|
test "a backend failure surfaces as an EmitError, not a backend error" {
  // Two sheets with the same name make the backend reject the second one; the
  // seam must translate that into the pipeline's own error type.
  let wb = @model.Workbook::new()
  wb.add_sheet("Dup") |> ignore
  wb.add_sheet("Dup") |> ignore
  let caught = try {
    @emit.to_bytes(wb) |> ignore
    None
  } catch {
    @diag.EmitError(d) => Some(d.render())
  }
  assert_true(caught is Some(_))
}
