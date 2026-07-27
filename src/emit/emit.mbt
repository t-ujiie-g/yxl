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
    // A limit of the backend that we describe ourselves, already worded for
    // the reader; it passes through rather than being wrapped again.
    @diag.EmitError(_) as ours => raise ours
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
/// Drive the backend: workbook-wide settings, one sheet per model sheet, then
/// serialize. Raises the backend's own error, which the seam boundary wraps,
/// or an `@diag.EmitError` where we have something better to say than it does.
fn build_workbook(wb : @model.Workbook) -> Bytes raise {
  let backend = @xlsx.Workbook::new()
  // Excel stores dates as serials relative to the workbook's epoch, so the
  // backend's flag must match the serials we compute (@units date system).
  if wb.date_system is Date1904 {
    backend.set_workbook_props(
      Some(@xlsx.WorkbookPropsOptions::with_values(date_1904=true)),
    )
  }
  if wb.default_font is Some(name) {
    backend.set_default_font(name)
  }
  if wb.properties is Some(properties) {
    apply_properties(backend, properties)
  }
  if wb.calc is Some(calc) {
    apply_calc(backend, calc)
  }
  if wb.protection is Some(protection) {
    apply_workbook_protection(backend, protection)
  }
  // One cache each for the whole workbook, so a style shared across sheets is
  // registered once (ADR-004). Cell styles and conditional formats live in
  // separate Excel tables, so they cannot share a cache.
  let style_ids : Map[@model.Style, Int] = Map([])
  let dxf_ids : Map[@model.Style, Int] = Map([])
  for sheet in wb.sheets {
    backend.new_sheet(sheet.name) |> ignore
    emit_sheet(backend, sheet, style_ids, dxf_ids, wb.date_system)
  }
  // Pivots come after every sheet's cells: the backend reads each field's name
  // out of the source's header row, and a pivot routinely summarizes a sheet
  // declared after the one it sits on.
  for sheet in wb.sheets {
    for pivot in sheet.pivots {
      apply_pivot(backend, sheet.name, pivot)
    }
  }
  // Hidden tabs come after every sheet exists: the backend rejects hiding the
  // last visible sheet, and a sheet declared later may be the visible one.
  for sheet in wb.sheets {
    match sheet.visibility {
      Visible => ()
      Hidden => backend.set_sheet_visible(sheet.name, false)
      VeryHidden =>
        backend.set_sheet_visible(sheet.name, false, very_hidden=true)
    }
  }
  // The tab Excel opens on, as an index into the sheet order.
  if wb.active_sheet is Some(name) {
    backend.set_active_sheet(backend.sheet_index(name))
  }
  // Workbook defined names (ADR-013): each named value/formula the spec declared
  // once, shared across the workbook and referenced by cells as `=name`.
  for defined_name in wb.defined_names {
    backend.set_defined_name(
      @xlsx.DefinedName::new(
        defined_name.name,
        refers_to(defined_name.refers_to, wb.date_system),
      ),
    )
  }
  @xlsx.write(backend)
}

///|
/// Write one sheet into the backend: its column and row bands, its cells, then
/// everything layered over them (merges, panes, view, tab color, page setup).
/// The sheet must already exist in `backend`.
fn emit_sheet(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  style_ids : Map[@model.Style, Int],
  dxf_ids : Map[@model.Style, Int],
  date_system : @units.DateSystem,
) -> Unit raise {
  // Column and row bands: one backend call per property per column/row in the
  // span. A band's default style shares the cell style cache, so a column style
  // equal to a cell style reuses the same id (ADR-004).
  for band in sheet.columns {
    let style_id = band_style_id(backend, style_ids, band)
    for col in band.first..<=band.last {
      if style_id is Some(id) {
        backend.set_col_style(sheet.name, col, id)
      }
      if band.size is Some(width) {
        backend.set_col_width(sheet.name, col, width)
      }
      if band.hidden is Some(hidden) {
        backend.set_col_visible(sheet.name, col, !hidden)
      }
      if band.outline_level is Some(level) {
        backend.set_col_outline_level(sheet.name, col, level)
      }
    }
  }
  for band in sheet.rows {
    let style_id = band_style_id(backend, style_ids, band)
    for row in band.first..<=band.last {
      if style_id is Some(id) {
        backend.set_row_style(sheet.name, row, id)
      }
      if band.size is Some(height) {
        backend.set_row_height(sheet.name, row, height)
      }
      if band.hidden is Some(hidden) {
        backend.set_row_visible(sheet.name, row, !hidden)
      }
      if band.outline_level is Some(level) {
        backend.set_row_outline_level(sheet.name, row, level)
      }
    }
  }
  for cell in sheet.cells {
    emit_cell(backend, sheet.name, cell, style_ids, date_system)
  }
  // Merge after the cells are written so the top-left keeps its value.
  for merge in sheet.merges {
    backend.merge_cell(
      sheet.name,
      merge.top_left.to_a1(),
      merge.bottom_right.to_a1(),
    )
  }
  if sheet.panes is Some(panes) {
    backend.set_panes(sheet.name, build_panes(panes))
  }
  if sheet.gridlines is Some(shown) {
    backend.set_sheet_view(
      sheet.name,
      LAST_SHEET_VIEW,
      @xlsx.SheetViewOptions::with_values(show_grid_lines=shown),
    )
  }
  if sheet.tab_color is Some(color) {
    backend.set_sheet_props(
      sheet.name,
      Some(@xlsx.SheetPropsOptions::with_values(tab_color_rgb=color.hex())),
    )
  }
  if sheet.page is Some(page) {
    apply_page_setup(backend, sheet.name, page)
  }
  if sheet.filter is Some(range) {
    apply_filter(backend, sheet.name, range)
  }
  // Tables come after the cells: the backend takes each column's name from the
  // header cell already written there.
  for table in sheet.tables {
    apply_table(backend, sheet.name, table)
  }
  for chart in sheet.charts {
    apply_chart(backend, sheet.name, chart)
  }
  for image in sheet.images {
    apply_image(backend, sheet.name, image)
  }
  for shape in sheet.shapes {
    apply_shape(backend, sheet.name, shape)
  }
  if sheet.background is Some(background) {
    apply_background(backend, sheet.name, background)
  }
  for group in sheet.sparklines {
    apply_sparkline_group(backend, sheet.name, group)
  }
  for control in sheet.controls {
    apply_control(backend, sheet.name, control)
  }
  for validation in sheet.validations {
    apply_validation(backend, sheet.name, validation, date_system)
  }
  for format in sheet.conditional_formats {
    apply_conditional_format(backend, sheet.name, format, dxf_ids, date_system)
  }
  for comment in sheet.comments {
    apply_comment(backend, sheet.name, comment)
  }
  if sheet.protection is Some(protection) {
    apply_sheet_protection(backend, sheet.name, protection)
  }
  // Links come after the merges: the backend redirects a link landing inside a
  // merged region to that region's anchor cell, which it can only do once the
  // merge is registered.
  for link in sheet.links {
    apply_link(backend, sheet.name, link)
  }
}

///|
/// Write one cell: its value in whichever backend form the kind calls for, then
/// its style id if it has one.
fn emit_cell(
  backend : @xlsx.Workbook,
  sheet_name : String,
  cell : @model.Cell,
  style_ids : Map[@model.Style, Int],
  date_system : @units.DateSystem,
) -> Unit raise {
  let reference = cell.pos.to_a1()
  match cell.value {
    Text(text) => backend.set_cell_value(sheet_name, reference, String(text))
    Number(number) =>
      backend.set_cell_value(sheet_name, reference, Numeric(number))
    Bool(flag) => backend.set_cell_value(sheet_name, reference, Bool(flag))
    Date(datetime) =>
      backend.set_cell_value(
        sheet_name,
        reference,
        Numeric(datetime.to_serial(date_system)),
      )
    Error(text) => backend.set_cell_value(sheet_name, reference, Error(text))
    Formula(formula~, cached~) =>
      backend.set_cell_formula(
        sheet_name,
        reference,
        formula,
        value?=cached.map(value => render_cached(value, date_system)),
      )
    RichText(runs) =>
      backend.set_cell_rich_text(
        sheet_name,
        reference,
        runs.map(build_rich_run)[:],
      )
  }
  if cell.style is Some(style) {
    backend.set_cell_style(
      sheet_name,
      reference,
      intern_style(backend, style_ids, style),
    )
  }
}

///|
/// The Excel `refers_to` expression for a defined name's target. A constant
/// becomes its formula literal — a string is quoted (inner quotes doubled, per
/// Excel), a number/bool/date its literal — and a formula is its body verbatim.
fn refers_to(
  value : @model.CellValue,
  date_system : @units.DateSystem,
) -> String {
  match value {
    Text(text) => quote_literal(text)
    Number(number) => number.to_string()
    Bool(flag) => if flag { "TRUE" } else { "FALSE" }
    Date(datetime) => datetime.to_serial(date_system).to_string()
    Error(text) => text
    Formula(formula~, ..) => formula
    RichText(_) => ""
  }
}

///|
/// The backend indexes a sheet's views; `-1` addresses the last (and, for a
/// workbook we build ourselves, only) one.
const LAST_SHEET_VIEW : Int = -1

///|
/// Twips — 1/20 of a point — are the unit OOXML gives a split position in
/// (ECMA-376 §18.3.1.66). The model speaks points, so the conversion belongs
/// here, behind the backend seam.
const TWIPS_PER_POINT : Double = 20.0

///|
/// A model pane configuration as the backend's `Panes`. Freezing at a cell
/// splits off the columns to its left and the rows above it — Excel counts those
/// as the split, and the frozen corner cell becomes the scrolling pane's
/// top-left. A split is positioned in twips instead.
fn build_panes(panes : @model.Panes) -> @xlsx.Panes {
  match panes {
    Freeze(cell) => {
      let x_split = cell.col - 1
      let y_split = cell.row - 1
      @xlsx.Panes::with_values(
        freeze=true,
        x_split~,
        y_split~,
        top_left_cell=cell.to_a1(),
        active_pane=active_pane(x_split, y_split),
      )
    }
    Split(x~, y~) => {
      let x_split = (x * TWIPS_PER_POINT).to_int()
      let y_split = (y * TWIPS_PER_POINT).to_int()
      @xlsx.Panes::with_values(
        split=true,
        x_split~,
        y_split~,
        active_pane=active_pane(x_split, y_split),
      )
    }
  }
}

///|
/// Which pane Excel puts the cursor in: the scrolling one, named by where it
/// sits relative to the split(s).
fn active_pane(x_split : Int, y_split : Int) -> String {
  match (x_split > 0, y_split > 0) {
    (true, true) => "bottomRight"
    (true, false) => "topRight"
    (false, _) => "bottomLeft"
  }
}
