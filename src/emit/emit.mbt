///|
/// The emitter seam (ADR-002): turn a resolved `model` into `.xlsx` bytes. Every
/// backend access lives behind this interface, so the pipeline never calls the
/// Excel library directly and the backend stays swappable. Implementations
/// report failures as `@diag.EmitError`, never as a backend-specific error.
pub trait Emitter {
  fn emit(Self, @model.Workbook) -> Bytes raise @diag.EmitError
}

///|
/// The `bobzhang/mbtexcel`-backed emitter — the single place `@xlsx` is touched.
pub struct MbtexcelEmitter {}

///|
/// The default emitter.
pub fn MbtexcelEmitter::new() -> MbtexcelEmitter {
  MbtexcelEmitter::{  }
}

///|
pub impl Emitter for MbtexcelEmitter with fn emit(_self, wb) {
  build_workbook(wb) catch {
    err => {
      // Upcast to `Error` for its `Show`; the concrete `XlsxError` has none.
      let reason : Error = err
      raise @diag.EmitError(
        @diag.Diagnostic::new("Excel backend: " + reason.to_string()),
      )
    }
  }
}

///|
/// Emit a workbook to `.xlsx` bytes using the default backend — the convenient
/// entry point when a caller does not care which backend is used.
pub fn to_bytes(wb : @model.Workbook) -> Bytes raise @diag.EmitError {
  MbtexcelEmitter::new().emit(wb)
}

///|
/// Drive the backend: one sheet per model sheet, one cell per model cell, then
/// serialize. Raises the backend's own error; the seam boundary wraps it.
fn build_workbook(wb : @model.Workbook) -> Bytes raise @xlsx.XlsxError {
  let backend = @xlsx.Workbook::new()
  for sheet in wb.sheets {
    backend.new_sheet(sheet.name) |> ignore
    for cell in sheet.cells {
      let value = match cell.value {
        Text(text) => @xlsx.CellValue::String(text)
        Number(number) => @xlsx.CellValue::Numeric(number)
        Bool(flag) => @xlsx.CellValue::Bool(flag)
      }
      backend.set_cell_value(sheet.name, cell.pos.to_a1(), value)
    }
  }
  @xlsx.write(backend)
}
