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
///
/// Number-format codes are interned: each distinct code is registered as a style
/// exactly once and reused across every cell that names it, so a format declared
/// many times compiles to a single style id, not N copies (ADR-004).
fn build_workbook(wb : @model.Workbook) -> Bytes raise @xlsx.XlsxError {
  let backend = @xlsx.Workbook::new()
  // Excel stores dates as serials relative to the workbook's epoch, so the
  // backend's flag must match the serials we compute (@units date system).
  if wb.date_system is Date1904 {
    backend.set_workbook_props(
      Some(@xlsx.WorkbookPropsOptions::with_values(date_1904=true)),
    )
  }
  let style_ids : Map[String, Int] = Map([])
  for sheet in wb.sheets {
    backend.new_sheet(sheet.name) |> ignore
    for cell in sheet.cells {
      let reference = cell.pos.to_a1()
      match cell.value {
        Text(text) =>
          backend.set_cell_value(sheet.name, reference, String(text))
        Number(number) =>
          backend.set_cell_value(sheet.name, reference, Numeric(number))
        Bool(flag) => backend.set_cell_value(sheet.name, reference, Bool(flag))
        Date(datetime) =>
          backend.set_cell_value(
            sheet.name,
            reference,
            Numeric(datetime.to_serial(wb.date_system)),
          )
        Formula(formula~, cached~) =>
          backend.set_cell_formula(
            sheet.name,
            reference,
            formula,
            value?=cached.map(value => render_cached(value, wb.date_system)),
          )
      }
      if cell.format is Some(format) {
        let style_id = match style_ids.get(format) {
          Some(id) => id
          None => {
            let id = backend.add_style(@xlsx.Style::number_format(format))
            style_ids[format] = id
            id
          }
        }
        backend.set_cell_style(sheet.name, reference, style_id)
      }
    }
  }
  @xlsx.write(backend)
}

///|
/// Render a formula's cached result as the string the backend stores in `<v>`.
/// Only scalar caches occur in practice; a date renders to its serial.
fn render_cached(
  value : @model.CellValue,
  date_system : @units.DateSystem,
) -> String {
  match value {
    Text(text) => text
    Number(number) => number.to_string()
    Bool(flag) => if flag { "TRUE" } else { "FALSE" }
    Date(datetime) => datetime.to_serial(date_system).to_string()
    Formula(..) => ""
  }
}
