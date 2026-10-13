///|
/// A cell's style, compared structurally so equal looks intern to one `cellXfs`
/// id (ADR-004). `cleared` holds attributes explicitly unset (ADR-020), never
/// also set.
pub(all) struct Style {
  font : Font?
  fill : Fill?
  borders : Borders?
  align : Alignment?
  number_format : String?
  protection : CellProtection?
  cleared : StyleAttrs
} derive(Eq, Hash, Debug)

///|
/// A cell's half of sheet protection (Format Cells → Protection); inert until
/// the sheet is protected.
pub(all) struct CellProtection {
  locked : Bool?
  hidden : Bool?
} derive(Eq, Hash, Debug)

///|
/// The empty style — every attribute defaulted. Equal to a `Style` with all
/// `None` fields, so it interns with any other empty style.
pub fn Style::empty() -> Style {
  {
    font: None,
    fill: None,
    borders: None,
    align: None,
    number_format: None,
    protection: None,
    cleared: StyleAttrs::none(),
  }
}

///|
/// A style carrying only a number-format code — the common shorthand.
pub fn Style::number_format(code : String) -> Style {
  { ..Style::empty(), number_format: Some(code), }
}

///|
/// Whether the style sets nothing and clears nothing (equal to `empty`). Such a
/// style needs no `cellXfs` entry; the emitter leaves the cell on the default
/// style.
pub fn Style::is_empty(self : Style) -> Bool {
  self == Style::empty()
}

///|
/// Lay `self` over `base`: what it sets wins, what it clears goes, the rest shows
/// through. Fonts, alignments and border edges merge per attribute.
pub fn Style::over(self : Style, base : Style) -> Style {
  (
    {
      font: merge_font(base.font, self.font, self.cleared),
      align: merge_align(base.align, self.align, self.cleared),
      borders: merge_borders(base.borders, self.borders, self.cleared),
      fill: pick(base.fill, self.fill, self.cleared.has(Fill)),
      number_format: pick(
        base.number_format,
        self.number_format,
        self.cleared.has(NumberFormat),
      ),
      protection: merge_protection(
        base.protection,
        self.protection,
        self.cleared,
      ),
      cleared: StyleAttrs::none(),
    } : Style).clearing(self.cleared.union(base.cleared))
}

///|
/// `over` laid on `under` where either may be absent: whichever is present, or
/// `None` when neither is.
pub fn Style::layer(under : Style?, over : Style?) -> Style? {
  match (under, over) {
    (Some(under), Some(over)) => Some(over.over(under))
    (None, over) => over
    (under, None) => under
  }
}

///|
/// What a band passes to a cell holding `value`: all of it, except a number
/// format landing on text, which Excel ignores (ECMA-376 §18.8.31) and the
/// backend would render as the literal code.
pub fn Style::inherited_by(self : Style, value : CellValue) -> Style {
  guard value is (Text(_) | RichText(_)) else { return self }
  guard self.number_format is Some(code) && !has_text_section(code) else {
    return self
  }
  { ..self, number_format: None, }
}

///|
/// Whether a number-format code has the fourth section that governs text. The
/// separators counted are the top-level `;` only — one inside a quoted literal
/// (`"a;b"`) or escaped (`\;`) is part of a section, not a break between two.
fn has_text_section(code : String) -> Bool {
  let mut sections = 1
  let mut quoted = false
  let mut escaped = false
  for ch in code {
    if escaped {
      escaped = false
      continue
    }
    match ch {
      '\\' => escaped = true
      '"' => quoted = !quoted
      ';' => if !quoted { sections += 1 }
      _ => ()
    }
  }
  sections >= 4
}

///|
/// One attribute's three-way choice: the overriding value if it has one,
/// nothing if the overriding style cleared it, else the base's.
fn[T] pick(base : T?, over : T?, cleared : Bool) -> T? {
  match over {
    Some(_) => over
    None => if cleared { None } else { base }
  }
}

///|
/// A font laid over another, attribute by attribute, with the overriding style's
/// cleared attributes taken away — as for the alignment, borders, and protection
/// below.
fn merge_font(base : Font?, over : Font?, cleared : StyleAttrs) -> Font? {
  let base = base.unwrap_or(Font::empty())
  let over = over.unwrap_or(Font::empty())
  normalize_font({
    bold: pick(base.bold, over.bold, cleared.has(FontBold)),
    italic: pick(base.italic, over.italic, cleared.has(FontItalic)),
    underline: pick(base.underline, over.underline, cleared.has(FontUnderline)),
    strike: pick(base.strike, over.strike, cleared.has(FontStrike)),
    size: pick(base.size, over.size, cleared.has(FontSize)),
    name: pick(base.name, over.name, cleared.has(FontName)),
    color: pick(base.color, over.color, cleared.has(FontColor)),
  })
}

///|
fn merge_align(
  base : Alignment?,
  over : Alignment?,
  cleared : StyleAttrs,
) -> Alignment? {
  let base = base.unwrap_or(Alignment::empty())
  let over = over.unwrap_or(Alignment::empty())
  normalize_align({
    horizontal: pick(
      base.horizontal,
      over.horizontal,
      cleared.has(AlignHorizontal),
    ),
    vertical: pick(base.vertical, over.vertical, cleared.has(AlignVertical)),
    wrap: pick(base.wrap, over.wrap, cleared.has(AlignWrap)),
  })
}

///|
fn merge_borders(
  base : Borders?,
  over : Borders?,
  cleared : StyleAttrs,
) -> Borders? {
  let base = base.unwrap_or(Borders::empty())
  let over = over.unwrap_or(Borders::empty())
  normalize_borders({
    left: pick(base.left, over.left, cleared.has(BorderLeft)),
    right: pick(base.right, over.right, cleared.has(BorderRight)),
    top: pick(base.top, over.top, cleared.has(BorderTop)),
    bottom: pick(base.bottom, over.bottom, cleared.has(BorderBottom)),
  })
}

///|
fn merge_protection(
  base : CellProtection?,
  over : CellProtection?,
  cleared : StyleAttrs,
) -> CellProtection? {
  let base = base.unwrap_or(CellProtection::empty())
  let over = over.unwrap_or(CellProtection::empty())
  normalize_protection({
    locked: pick(base.locked, over.locked, cleared.has(ProtectionLocked)),
    hidden: pick(base.hidden, over.hidden, cleared.has(ProtectionHidden)),
  })
}

///|
/// A group that ended up setting nothing is `None`, not an empty group: the two
/// draw the same cell, and only one of them interns as the default style.
fn normalize_font(font : Font) -> Font? {
  if font.is_empty() {
    None
  } else {
    Some(font)
  }
}

///|
fn normalize_align(align : Alignment) -> Alignment? {
  if align == Alignment::empty() {
    None
  } else {
    Some(align)
  }
}

///|
fn normalize_borders(borders : Borders) -> Borders? {
  if borders == Borders::empty() {
    None
  } else {
    Some(borders)
  }
}

///|
fn normalize_protection(protection : CellProtection) -> CellProtection? {
  if protection == CellProtection::empty() {
    None
  } else {
    Some(protection)
  }
}

///|
/// A font: bold/italic/underline/strike toggles, a point size, a face name, and
/// a color. Each is optional; an unset attribute inherits the workbook default.
pub(all) struct Font {
  bold : Bool?
  italic : Bool?
  underline : Bool?
  strike : Bool?
  size : Double?
  name : String?
  color : @units.Color?
} derive(Eq, Hash, Debug)

///|
/// The empty font — every attribute defaulted, so it inherits everything from
/// whatever the cell already wears. Spelling all seven fields out to set one of
/// them is the kind of noise that hides which attribute was the point.
pub fn Font::empty() -> Font {
  {
    bold: None,
    italic: None,
    underline: None,
    strike: None,
    size: None,
    name: None,
    color: None,
  }
}

///|
/// Whether the font sets nothing (equal to `empty`).
pub fn Font::is_empty(self : Font) -> Bool {
  self == Font::empty()
}

///|
/// A solid cell fill in a single color.
pub(all) struct Fill {
  color : @units.Color
} derive(Eq, Hash, Debug)

///|
/// Cell alignment: horizontal and vertical placement, plus text wrapping.
pub(all) struct Alignment {
  horizontal : HAlign?
  vertical : VAlign?
  wrap : Bool?
} derive(Eq, Hash, Debug)

///|
/// The empty alignment — Excel's own placement.
pub fn Alignment::empty() -> Alignment {
  { horizontal: None, vertical: None, wrap: None, }
}

///|
/// Horizontal text alignment within a cell.
pub(all) enum HAlign {
  Left
  Center
  Right
  Fill
  Justify
  Distributed
} derive(Eq, Hash, Debug)

///|
/// Vertical text alignment within a cell.
pub(all) enum VAlign {
  Top
  Middle
  Bottom
  Justify
  Distributed
} derive(Eq, Hash, Debug)

///|
/// The four cell borders, each optionally styled. `None` for a side means no
/// border on that side.
pub(all) struct Borders {
  left : Border?
  right : Border?
  top : Border?
  bottom : Border?
} derive(Eq, Hash, Debug)

///|
/// No border on any side.
pub fn Borders::empty() -> Borders {
  { left: None, right: None, top: None, bottom: None, }
}

///|
/// The protection that changes nothing: Excel's own defaults.
pub fn CellProtection::empty() -> CellProtection {
  { locked: None, hidden: None, }
}

///|
/// One border edge: a line style and an optional color (black by default).
pub(all) struct Border {
  style : BorderStyle
  color : @units.Color?
} derive(Eq, Hash, Debug)

///|
/// A border line style — the subset of Excel's line styles worth naming.
pub(all) enum BorderStyle {
  Thin
  Medium
  Thick
  Dashed
  Dotted
  Double
  Hair
} derive(Eq, Hash, Debug)
