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
        Error(text) =>
          backend.set_cell_value(sheet.name, reference, Error(text))
        Formula(formula~, cached~) =>
          backend.set_cell_formula(
            sheet.name,
            reference,
            formula,
            value?=cached.map(value => render_cached(value, wb.date_system)),
          )
      }
      if cell.format is Some(format) {
        let style_id = intern_format_style(backend, style_ids, format)
        backend.set_cell_style(sheet.name, reference, style_id)
      }
    }
  }
  @xlsx.write(backend)
}

///|
/// Register a number-format code as a style the first time it is seen and reuse
/// its id thereafter (ADR-004): the same format code always maps to the same
/// `cellXfs` id, so a format declared many times is not copied N ways.
fn intern_format_style(
  backend : @xlsx.Workbook,
  cache : Map[String, Int],
  format : String,
) -> Int {
  match cache.get(format) {
    Some(id) => id
    None => {
      let id = backend.add_style(@xlsx.Style::number_format(format))
      cache[format] = id
      id
    }
  }
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
    Error(text) => text
    Formula(..) => ""
  }
}
