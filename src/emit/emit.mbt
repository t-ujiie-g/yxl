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
  let style_ids : Map[@model.Style, Int] = Map([])
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
        RichText(runs) =>
          backend.set_cell_rich_text(
            sheet.name,
            reference,
            runs.map(build_rich_run)[:],
          )
      }
      if cell.style is Some(style) {
        let style_id = intern_style(backend, style_ids, style)
        backend.set_cell_style(sheet.name, reference, style_id)
      }
    }
  }
  @xlsx.write(backend)
}

///|
/// Register a style the first time it is seen and reuse its id thereafter
/// (ADR-004): equal styles always map to the same `cellXfs` id, so a look
/// declared many times is not copied N ways. The cache keys on the model style,
/// which compares and hashes structurally.
fn intern_style(
  backend : @xlsx.Workbook,
  cache : Map[@model.Style, Int],
  style : @model.Style,
) -> Int {
  match cache.get(style) {
    Some(id) => id
    None => {
      let id = backend.add_style(build_style(style))
      cache[style] = id
      id
    }
  }
}

///|
/// Translate a model style into the backend's `Style`. A number format, if any,
/// seeds the style; font, fill, borders, and alignment are layered on.
fn build_style(style : @model.Style) -> @xlsx.Style {
  let mut backend = match style.number_format {
    Some(code) => @xlsx.Style::number_format(code)
    None => @xlsx.Style::new()
  }
  if style.font is Some(font) {
    backend = backend.with_font(build_font(font))
  }
  if style.fill is Some(fill) {
    backend = backend.with_fill(@xlsx.Fill::solid(fill.color.hex()))
  }
  if style.borders is Some(borders) {
    backend = backend.with_border(build_borders(borders))
  }
  if style.align is Some(align) {
    backend = backend.with_alignment(build_alignment(align))
  }
  backend
}

///|
/// A model font as the backend's `Font`. The face name maps to the backend's
/// `family` field; underline is expressed as its OOXML style string.
fn build_font(font : @model.Font) -> @xlsx.Font {
  @xlsx.Font::with_values(
    bold?=font.bold,
    italic?=font.italic,
    strike?=font.strike,
    underline?=font.underline.map(on => if on { "single" } else { "none" }),
    size?=font.size,
    color?=font.color.map(color => color.hex()),
    family?=font.name,
  )
}

///|
/// A model alignment as the backend's `Alignment`.
fn build_alignment(align : @model.Alignment) -> @xlsx.Alignment {
  @xlsx.Alignment::with_values(
    horizontal?=align.horizontal.map(horizontal_code),
    vertical?=align.vertical.map(vertical_code),
    wrap_text?=align.wrap,
  )
}

///|
/// The four model border edges as the backend's per-edge `Border` array; only
/// the sides that are set contribute an entry.
fn build_borders(borders : @model.Borders) -> Array[@xlsx.Border] {
  let edges = []
  fn push(side : String, border : @model.Border?) -> Unit {
    if border is Some(b) {
      edges.push(
        @xlsx.Border::with_values(
          side,
          color?=b.color.map(color => color.hex()),
          style=border_style_code(b.style),
        ),
      )
    }
  }

  push("left", borders.left)
  push("right", borders.right)
  push("top", borders.top)
  push("bottom", borders.bottom)
  edges
}

///|
/// The OOXML horizontal-alignment attribute for a model `HAlign`.
fn horizontal_code(align : @model.HAlign) -> String {
  match align {
    Left => "left"
    Center => "center"
    Right => "right"
    Fill => "fill"
    Justify => "justify"
    Distributed => "distributed"
  }
}

///|
/// The OOXML vertical-alignment attribute for a model `VAlign` (Excel spells
/// vertical centering `center`).
fn vertical_code(align : @model.VAlign) -> String {
  match align {
    Top => "top"
    Middle => "center"
    Bottom => "bottom"
    Justify => "justify"
    Distributed => "distributed"
  }
}

///|
/// The excelize border line-style code for a model `BorderStyle`.
fn border_style_code(style : @model.BorderStyle) -> Int {
  match style {
    Thin => 1
    Medium => 2
    Dashed => 3
    Dotted => 4
    Thick => 5
    Double => 6
    Hair => 7
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
    Formula(..) | RichText(_) => ""
  }
}

///|
/// A model rich-text run as the backend's `RichTextRun`.
fn build_rich_run(run : @model.RichRun) -> @xlsx.RichTextRun {
  { text: run.text, font: run.font.map(build_rich_font) }
}

///|
/// A model font as the backend's `RichTextFont` (a per-run font). The backend's
/// toggles are non-optional, so an unset toggle becomes `false`.
fn build_rich_font(font : @model.Font) -> @xlsx.RichTextFont {
  {
    bold: font.bold.unwrap_or(false),
    italic: font.italic.unwrap_or(false),
    strike: font.strike.unwrap_or(false),
    outline: false,
    shadow: false,
    condense: false,
    extended: false,
    underline: font.underline.map(on => if on { "single" } else { "none" }),
    size: font.size,
    color: font.color.map(color => color.hex()),
    color_theme: None,
    color_indexed: None,
    color_tint: None,
    charset: None,
    family_number: None,
    scheme: None,
    vert_align: None,
    family: font.name,
  }
}
