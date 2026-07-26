// Turning a model style into the backend's: the `cellXfs` interning that makes
// reuse compile to a single shared style id (ADR-004), plus the per-attribute
// translation (font, fill, border, alignment) and the OOXML attribute codes the
// backend expects as strings. The pipeline's own style vocabulary lives in
// `@model`; nothing here escapes the emitter seam.

///|
/// The interned style id for a band's default style, or `None` when the band
/// sets no style. Interned once per band, not once per column/row it covers.
fn band_style_id(
  backend : @xlsx.Workbook,
  cache : Map[@model.Style, Int],
  band : @model.AxisBand,
) -> Int? raise {
  match band.style {
    Some(style) => Some(intern_style(backend, cache, style))
    None => None
  }
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
) -> Int raise {
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
/// The interned *differential* format id for a conditional format's style
/// (ADR-004, in Excel's `dxfs` table rather than `cellXfs`). Kept in its own
/// cache because the two tables are indexed separately: an id from one means
/// nothing in the other.
fn intern_conditional_style(
  backend : @xlsx.Workbook,
  cache : Map[@model.Style, Int],
  style : @model.Style,
) -> Int raise {
  match cache.get(style) {
    Some(id) => id
    None => {
      let id = backend.new_conditional_style(build_style(style))
      cache[style] = id
      id
    }
  }
}

///|
/// Translate a model style into the backend's `Style`. A number format, if any,
/// seeds the style; font, fill, borders, and alignment are layered on.
fn build_style(style : @model.Style) -> @xlsx.Style raise @diag.EmitError {
  let mut backend = match (style.number_format, protection_to_set(style)) {
    // The backend builds a style by seeding it from one attribute and layering
    // the rest with `with_*` builders — and it has no `with_protection`, so
    // protection can only be the seed. A style needing both cannot be built.
    (Some(code), Some(_)) =>
      raise @diag.EmitError(
        @diag.Diagnostic::new(
          "the Excel backend cannot put a number format and cell protection in one style; " +
          "split the number format ('\{code}') into a separate style, or drop it from this one",
        ),
      )
    (None, Some(protection)) => @xlsx.Style::protection(protection)
    (Some(code), None) => @xlsx.Style::number_format(code)
    (None, None) => @xlsx.Style::new()
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
/// The backend protection a style actually needs written, or `None` when it
/// asks only for Excel's own defaults. Excel locks every cell and hides no
/// formula, so a style saying exactly that changes nothing and need not occupy
/// the one seed slot the backend gives us.
fn protection_to_set(style : @model.Style) -> @xlsx.Protection? {
  guard style.protection is Some(protection) else { return None }
  let locked = protection.locked.unwrap_or(true)
  let hidden = protection.hidden.unwrap_or(false)
  if locked && !hidden {
    None
  } else {
    Some(@xlsx.Protection::with_values(locked~, hidden~))
  }
}

///|
/// A model font as the backend's `Font`. The face name maps to the backend's
/// `family` field; underline is expressed as its OOXML style string.
fn build_font(font : @model.Font) -> @xlsx.Font {
  @xlsx.Font::with_values(
    bold?=font.bold,
    italic?=font.italic,
    strike?=font.strike,
    underline?=font.underline.map(underline_code),
    size?=font.size,
    color?=font.color.map(color => color.hex()),
    family?=font.name,
  )
}

///|
/// The OOXML underline-style attribute for a model font's underline toggle.
fn underline_code(on : Bool) -> String {
  if on {
    "single"
  } else {
    "none"
  }
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
    underline: font.underline.map(underline_code),
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
