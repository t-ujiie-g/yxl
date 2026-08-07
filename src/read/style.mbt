// Recovering a cell's style, and interning it the way the spec would have
// declared it.
//
// The backend hands the *sharing* over for free: `get_cell_style` returns a
// style id, and equal ids mean equal styles, so the cells that wore one look in
// the original wear one `defs.styles` entry here. What the file does not carry
// is the **name** — the author's `header` became id 7 when it compiled — so the
// naming is `render`'s problem, not this package's. All this does is map id to
// style, once each.

///|
/// The styles met so far, keyed by the backend's own id. A style is translated
/// on first sight and reused thereafter, which is what makes the recovered spec
/// share what the original shared (ADR-004).
priv struct StyleTable {
  by_id : Map[Int, @model.Style?]
}

///|
fn StyleTable::new() -> StyleTable {
  { by_id: Map([]) }
}

///|
/// The style a cell wears, or `None` where it wears Excel's default.
fn read_cell_style(
  backend : @xlsx.Workbook,
  sheet_name : String,
  reference : String,
  styles : StyleTable,
  notes : Notes,
) -> @model.Style? raise {
  guard backend.get_cell_style(sheet_name, reference) is Some(id) else {
    return None
  }
  read_style_id(backend, id, styles, notes)
}

///|
/// The model style for one backend style id, translated once and cached.
fn read_style_id(
  backend : @xlsx.Workbook,
  id : Int,
  styles : StyleTable,
  notes : Notes,
) -> @model.Style? raise {
  // Id 0 is the default style every unstyled cell carries; recovering it would
  // put an empty `style: {}` on every cell in the workbook.
  guard id != 0 else { return None }
  if styles.by_id.get(id) is Some(cached) {
    return cached
  }
  let style = read_style(backend, backend.get_style(id), notes)
  let recovered = if style.is_empty() { None } else { Some(style) }
  styles.by_id[id] = recovered
  recovered
}

///|
/// One backend style as the schema can say it. Everything the schema has no
/// words for is dropped *and named*: a spec that quietly lost the gradient
/// behind a heading would be worse than one that says it did.
fn read_style(
  backend : @xlsx.Workbook,
  style : @xlsx.Style,
  notes : Notes,
) -> @model.Style {
  {
    font: read_font(backend, style.font, notes),
    fill: read_fill(backend, style.fill, notes),
    borders: read_borders(style.border, notes),
    align: read_alignment(style.alignment, notes),
    number_format: read_number_format(style, notes),
    protection: read_protection(style.protection),
  }
}

///|
/// A font, narrowed to what the schema holds. Underline is a *style* in Excel
/// (`single`, `double`, `singleAccounting`, …) and a plain flag here, so
/// anything but `single` is recorded as narrowed rather than silently squared
/// off.
fn read_font(
  backend : @xlsx.Workbook,
  font : @xlsx.Font?,
  notes : Notes,
) -> @model.Font? {
  guard font is Some(font) else { return None }
  let recovered : @model.Font = {
    bold: font.bold,
    italic: font.italic,
    underline: read_underline(font.underline, notes),
    strike: font.strike,
    size: font.size,
    name: font.family,
    color: resolve_color(
      backend,
      font.color,
      theme=font.color_theme,
      indexed=font.color_indexed,
      tint=font.color_tint,
      what="a font",
      notes~,
    ),
  }
  if font.outline is Some(true) ||
    font.shadow is Some(true) ||
    font.condense is Some(true) ||
    font.extended is Some(true) ||
    font.vert_align is Some(_) {
    notes.drop(
      "a font effect the spec has no word for (outline, shadow, condense, extend, or super/subscript)",
    )
  }
  if recovered.is_empty() {
    None
  } else {
    Some(recovered)
  }
}

///|
/// Excel's underline styles as the schema's on/off. `none` is off, `single` is
/// on, and anything else is on *and* narrowed.
fn read_underline(underline : String?, notes : Notes) -> Bool? {
  match underline {
    None => None
    Some("none") => None
    Some("single") => Some(true)
    Some(other) => {
      notes.drop("underline style '\{other}', narrowed to a plain underline")
      Some(true)
    }
  }
}

///|
/// A hex colour, when there is one to have.
///
/// A fully opaque alpha byte is dropped: the file writes SpreadsheetML colours
/// as `AARRGGBB` and `FF` there says nothing a spec needs to carry, so an
/// extracted spec spells a colour the way an author would. A partial alpha is
/// kept, since that one *is* a choice. Most of the backend's colour readers
/// have already trimmed the byte by the time they get here; the sheet tab's
/// has not.
fn read_color(color : String?, notes : Notes) -> @units.Color? {
  guard color is Some(text) && !text.is_empty() else { return None }
  match @units.Color::parse(text) {
    Some(color) =>
      if color.hex().has_prefix("FF") && color.hex().length() == 8 {
        @units.Color::parse(color.rgb())
      } else {
        Some(color)
      }
    None => {
      notes.drop("a colour written as '\{text}', which is not plain hex")
      None
    }
  }
}

///|
/// A colour the file may have written as an RGB value, as an index into the
/// workbook's theme, or as one into the legacy palette — resolved to RGB either
/// way, with the `tint` Excel lightens or darkens the base colour by applied
/// (ECMA-376 §18.3.1.15).
///
/// The spec carries RGB alone, so an unresolved index would be a lost colour;
/// resolving it here is what lets a workbook whose headings are all theme
/// colours — which is to say most real workbooks — come back looking like
/// itself. `what` names the thing wearing the colour, for the note left behind
/// when even the theme cannot say what it was: the hyperlink pair (`hlink`,
/// `folHlink`) is in the file's theme but not in the table the backend parses
/// out of it.
fn resolve_color(
  backend : @xlsx.Workbook,
  color : String?,
  theme~ : Int?,
  indexed~ : Int?,
  tint~ : Double?,
  what~ : String,
  notes~ : Notes,
) -> @units.Color? {
  if color is Some(text) && !text.is_empty() {
    return read_color(color, notes)
  }
  guard theme is Some(_) || indexed is Some(_) else { return None }
  // `get_base_color` answers the theme's or the palette's own spelling — the
  // theme's is `RRGGBB` and a `<indexedColors>` table's is `00RRGGBB` — and the
  // empty string where it can resolve neither index.
  let base = backend.get_base_color(
    "",
    indexed.unwrap_or(-1),
    theme_color?=theme,
  )
  guard @units.Color::parse(base) is Some(parsed) else {
    notes.drop(
      "\{what} colour given as a theme or palette index the workbook does not define",
    )
    return None
  }
  // `theme_color` applies the tint in HLS (ECMA-376 §18.3.1.15) and answers
  // `AARRGGBB`.
  read_color(Some(@xlsx.theme_color(parsed.rgb(), tint.unwrap_or(0.0))), notes)
}

///|
/// A fill, which the schema knows only as a single solid colour.
fn read_fill(
  backend : @xlsx.Workbook,
  fill : @xlsx.Fill?,
  notes : Notes,
) -> @model.Fill? {
  guard fill is Some(fill) else { return None }
  if fill.typ is Some("gradient") {
    notes.drop(
      "a gradient fill, which the spec expresses only as a solid colour",
    )
    return None
  }
  // Pattern 1 is a plain solid; anything else paints a texture through two
  // colours, of which only the foreground survives.
  if fill.pattern is Some(pattern) && pattern != 1 && pattern != 0 {
    notes.drop("a patterned fill, kept as its foreground colour alone")
  }
  let foreground = match fill.colors {
    Some(colors) if !colors.is_empty() => Some(colors[0])
    _ => None
  }
  match
    resolve_color(
      backend,
      foreground,
      theme=fill.fg_theme,
      indexed=fill.fg_indexed,
      tint=fill.fg_tint,
      what="a fill",
      notes~,
    ) {
    Some(color) => Some({ color, })
    None => None
  }
}

///|
/// The four edges the schema names, from the backend's list of sides.
fn read_borders(
  borders : Array[@xlsx.Border]?,
  notes : Notes,
) -> @model.Borders? {
  guard borders is Some(borders) && !borders.is_empty() else { return None }
  let mut left = None
  let mut right = None
  let mut top = None
  let mut bottom = None
  for border in borders {
    guard read_border(border, notes) is Some(edge) else { continue }
    match border.typ {
      "left" => left = Some(edge)
      "right" => right = Some(edge)
      "top" => top = Some(edge)
      "bottom" => bottom = Some(edge)
      other =>
        notes.drop(
          "a '\{other}' border, which the spec draws only on the four sides",
        )
    }
  }
  if left is None && right is None && top is None && bottom is None {
    None
  } else {
    Some({ left, right, top, bottom })
  }
}

///|
/// One edge. A style Excel has and the schema does not (dash-dot and its
/// relatives, the slanted double) is recorded rather than approximated.
fn read_border(border : @xlsx.Border, notes : Notes) -> @model.Border? {
  guard border.style is Some(code) else { return None }
  guard border_style(code) is Some(style) else {
    if code != 0 {
      notes.drop("border style \{code}, which the spec has no name for")
    }
    return None
  }
  Some({ style, color: read_color(border.color, notes) })
}

///|
/// The inverse of the emitter's border codes (`@emit`'s `border_style_code`).
fn border_style(code : Int) -> @model.BorderStyle? {
  match code {
    1 => Some(Thin)
    2 => Some(Medium)
    3 => Some(Dashed)
    4 => Some(Dotted)
    5 => Some(Thick)
    6 => Some(Double)
    7 => Some(Hair)
    _ => None
  }
}

///|
/// Alignment, narrowed to the horizontal, vertical, and wrap the schema knows.
fn read_alignment(align : @xlsx.Alignment?, notes : Notes) -> @model.Alignment? {
  guard align is Some(align) else { return None }
  if align.text_rotation is Some(rotation) && rotation != 0 {
    notes.drop("a rotated cell, which the spec cannot express")
  }
  if align.indent is Some(indent) && indent != 0 {
    notes.drop("an alignment indent, which the spec cannot express")
  }
  if align.shrink_to_fit is Some(true) {
    notes.drop("shrink-to-fit, which the spec cannot express")
  }
  let horizontal = match align.horizontal {
    None | Some("") | Some("general") => None
    Some("left") => Some(@model.HAlign::Left)
    Some("center") => Some(Center)
    Some("right") => Some(Right)
    Some("fill") => Some(Fill)
    Some("justify") => Some(Justify)
    Some("distributed") => Some(Distributed)
    Some(other) => {
      notes.drop(
        "horizontal alignment '\{other}', which the spec has no name for",
      )
      None
    }
  }
  let vertical = match align.vertical {
    None | Some("") => None
    Some("top") => Some(@model.VAlign::Top)
    // Excel's own word for the middle is `center`, as it is for the horizontal.
    Some("center") => Some(Middle)
    Some("bottom") => Some(Bottom)
    Some("justify") => Some(Justify)
    Some("distributed") => Some(Distributed)
    Some(other) => {
      notes.drop(
        "vertical alignment '\{other}', which the spec has no name for",
      )
      None
    }
  }
  let wrap = if align.wrap_text is Some(true) { Some(true) } else { None }
  if horizontal is None && vertical is None && wrap is None {
    None
  } else {
    Some({ horizontal, vertical, wrap })
  }
}

///|
/// Cell protection, kept only where it differs from Excel's defaults — every
/// cell is locked and no formula hidden, so saying that changes nothing.
fn read_protection(protection : @xlsx.Protection?) -> @model.CellProtection? {
  guard protection is Some(protection) else { return None }
  let locked = if protection.locked is Some(false) { Some(false) } else { None }
  let hidden = if protection.hidden is Some(true) { Some(true) } else { None }
  if locked is None && hidden is None {
    None
  } else {
    Some({ locked, hidden })
  }
}

///|
/// A number format as a code the spec can write. A custom code is already one;
/// a built-in is looked up in Excel's own table, since the spec has no way to
/// say "format 14" and the code it stands for is what an author would write.
fn read_number_format(style : @xlsx.Style, notes : Notes) -> String? {
  if style.custom_num_fmt is Some(code) && !code.is_empty() {
    return Some(code)
  }
  match style.number_format {
    Some(Custom(code)) => if code.is_empty() { None } else { Some(code) }
    Some(Builtin(id)) => builtin_number_format(id, notes)
    None =>
      match style.num_fmt {
        Some(id) => builtin_number_format(id, notes)
        None => None
      }
  }
}

///|
/// Excel's built-in number formats by id (ECMA-376 §18.8.30). Id 0 is General,
/// which is the absence of a format rather than one to write down. The gaps in
/// the table are ids Excel reserves and leaves locale-defined; there is no fixed
/// code to write for them, so they are reported instead of guessed at.
fn builtin_number_format(id : Int, notes : Notes) -> String? {
  guard id != 0 else { return None }
  for entry in builtin_number_formats {
    let (builtin, code) = entry
    if builtin == id {
      return Some(code)
    }
  }
  notes.drop(
    "built-in number format \{id}, whose code Excel decides by locale rather than fixing",
  )
  None
}

///|
/// The built-in number formats whose codes ECMA-376 §18.8.30 fixes.
///
/// Ids 37–40 are spelled as *Excel* writes them rather than as §18.8.30 prints
/// them: the standard shows a space where Office uses `_)`, the "as wide as a
/// `)`" padding that lines a positive number up with a parenthesised negative
/// one (MS-OI29500 §2.1.601). Excel maps a cell formatted `#,##0_);(#,##0)`
/// onto id 37 and writes no `numFmt` element, so the standard's spelling would
/// come back out of `extract` as a different — and visibly misaligned — format.
let builtin_number_formats : Array[(Int, String)] = [
  (1, "0"),
  (2, "0.00"),
  (3, "#,##0"),
  (4, "#,##0.00"),
  (9, "0%"),
  (10, "0.00%"),
  (11, "0.00E+00"),
  (12, "# ?/?"),
  (13, "# ??/??"),
  (14, "mm-dd-yy"),
  (15, "d-mmm-yy"),
  (16, "d-mmm"),
  (17, "mmm-yy"),
  (18, "h:mm AM/PM"),
  (19, "h:mm:ss AM/PM"),
  (20, "h:mm"),
  (21, "h:mm:ss"),
  (22, "m/d/yy h:mm"),
  (37, "#,##0_);(#,##0)"),
  (38, "#,##0_);[Red](#,##0)"),
  (39, "#,##0.00_);(#,##0.00)"),
  (40, "#,##0.00_);[Red](#,##0.00)"),
  (45, "mm:ss"),
  (46, "[h]:mm:ss"),
  (47, "mmss.0"),
  (48, "##0.0E+0"),
  (49, "@"),
]
