///|
/// A cell's style: any combination of a font, a solid fill, borders, an
/// alignment, an Excel number-format code, and what sheet protection does to
/// the cell. Every field is optional; `None` throughout is the default
/// (`General`) style. Styles are compared and hashed
/// structurally so the emitter can intern identical styles to a single Excel
/// `cellXfs` id (ADR-004) — declare a look once, reference it many times, emit
/// it once.
///
/// `number_format` is an Excel format code (`"#,##0.00"`, `"0%"`) and
/// `protection` is what sheet protection does to a cell wearing this style.
/// Both live in the style rather than on the cell — Excel's own arrangement —
/// so both intern with the rest of the look.
///
/// An attribute is in one of **three** states, not two: set to a value, not
/// mentioned, or explicitly not set. `cleared` holds the third — the attributes
/// this style takes *away* from whatever it is laid over, which is how a cell
/// says "no fill" under a column band that fills it (`docs/spec.md` §6, ADR-020).
/// Nothing is mentioned in both places: an attribute with a value is never in
/// `cleared`.
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
/// One leaf of a style — every attribute `docs/spec.md` §6 lets a spec set, at
/// the granularity layering works on. A style clears attributes one at a time,
/// so `font: { color: null }` takes the colour and leaves the size.
pub(all) enum StyleAttr {
  Fill
  NumberFormat
  FontBold
  FontItalic
  FontUnderline
  FontStrike
  FontSize
  FontName
  FontColor
  AlignHorizontal
  AlignVertical
  AlignWrap
  BorderLeft
  BorderRight
  BorderTop
  BorderBottom
  ProtectionLocked
  ProtectionHidden
} derive(Eq, Hash, Debug)

///|
/// A set of style attributes, as a bitmask over `StyleAttr`. A newtype rather
/// than a bare `Int` so it cannot be confused with an id or a count, and a
/// bitmask rather than a collection so a `Style` carrying one still compares and
/// hashes structurally — which is what lets the emitter intern styles (ADR-004).
pub struct StyleAttrs(UInt) derive(Eq, Hash, Debug)

///|
/// The bit one attribute occupies. Eighteen of the thirty-two are spoken for.
fn StyleAttr::bit(self : StyleAttr) -> UInt {
  match self {
    Fill => 1U
    NumberFormat => 1U << 1
    FontBold => 1U << 2
    FontItalic => 1U << 3
    FontUnderline => 1U << 4
    FontStrike => 1U << 5
    FontSize => 1U << 6
    FontName => 1U << 7
    FontColor => 1U << 8
    AlignHorizontal => 1U << 9
    AlignVertical => 1U << 10
    AlignWrap => 1U << 11
    BorderLeft => 1U << 12
    BorderRight => 1U << 13
    BorderTop => 1U << 14
    BorderBottom => 1U << 15
    ProtectionLocked => 1U << 16
    ProtectionHidden => 1U << 17
  }
}

///|
/// The empty set — a style that clears nothing.
pub fn StyleAttrs::none() -> StyleAttrs {
  StyleAttrs(0U)
}

///|
/// The set holding exactly these attributes.
pub fn StyleAttrs::of(attrs : Array[StyleAttr]) -> StyleAttrs {
  let mut bits = 0U
  for attr in attrs {
    bits = bits | attr.bit()
  }
  StyleAttrs(bits)
}

///|
/// Whether the set holds `attr`.
pub fn StyleAttrs::has(self : StyleAttrs, attr : StyleAttr) -> Bool {
  (self.0 & attr.bit()) != 0U
}

///|
/// Whether the set holds nothing.
pub fn StyleAttrs::is_empty(self : StyleAttrs) -> Bool {
  self.0 == 0U
}

///|
/// This set with `attr` added.
pub fn StyleAttrs::adding(self : StyleAttrs, attr : StyleAttr) -> StyleAttrs {
  StyleAttrs(self.0 | attr.bit())
}

///|
/// Everything in either set.
pub fn StyleAttrs::union(self : StyleAttrs, other : StyleAttrs) -> StyleAttrs {
  StyleAttrs(self.0 | other.0)
}

///|
/// Everything in this set that `other` does not hold.
pub fn StyleAttrs::except(self : StyleAttrs, other : StyleAttrs) -> StyleAttrs {
  StyleAttrs(self.0 & other.0.lnot())
}

///|
/// A cell's half of sheet protection — Excel's Format Cells → Protection tab.
/// Neither field does anything until the sheet is protected.
///
/// Excel locks every cell by default, so protecting a sheet freezes all of it;
/// the way to leave a form's input boxes editable is to give *them* a style
/// with `locked: false`.
///
/// `hidden` keeps the cell's formula out of the formula bar while protected —
/// the value still shows, and the file still contains the formula.
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
  { ..Style::empty(), number_format: Some(code) }
}

///|
/// Whether the style sets nothing and clears nothing (equal to `empty`). Such a
/// style needs no `cellXfs` entry; the emitter leaves the cell on the default
/// style.
pub fn Style::is_empty(self : Style) -> Bool {
  self == Style::empty()
}

///|
/// The attributes this style gives a value to — the opposite half of `cleared`.
pub fn Style::assigned(self : Style) -> StyleAttrs {
  let mut attrs = StyleAttrs::none()
  fn set(flag : Bool, attr : StyleAttr) -> Unit {
    if flag {
      attrs = attrs.adding(attr)
    }
  }

  set(self.fill is Some(_), Fill)
  set(self.number_format is Some(_), NumberFormat)
  if self.font is Some(font) {
    set(font.bold is Some(_), FontBold)
    set(font.italic is Some(_), FontItalic)
    set(font.underline is Some(_), FontUnderline)
    set(font.strike is Some(_), FontStrike)
    set(font.size is Some(_), FontSize)
    set(font.name is Some(_), FontName)
    set(font.color is Some(_), FontColor)
  }
  if self.align is Some(align) {
    set(align.horizontal is Some(_), AlignHorizontal)
    set(align.vertical is Some(_), AlignVertical)
    set(align.wrap is Some(_), AlignWrap)
  }
  if self.borders is Some(borders) {
    set(borders.left is Some(_), BorderLeft)
    set(borders.right is Some(_), BorderRight)
    set(borders.top is Some(_), BorderTop)
    set(borders.bottom is Some(_), BorderBottom)
  }
  if self.protection is Some(protection) {
    set(protection.locked is Some(_), ProtectionLocked)
    set(protection.hidden is Some(_), ProtectionHidden)
  }
  attrs
}

///|
/// This style with `attr` explicitly not set: whatever value it held for that
/// attribute is dropped, and nothing it is laid over can supply one.
pub fn Style::without(self : Style, attr : StyleAttr) -> Style {
  let dropped : Style = match attr {
    Fill => { ..self, fill: None }
    NumberFormat => { ..self, number_format: None }
    FontBold
    | FontItalic
    | FontUnderline
    | FontStrike
    | FontSize
    | FontName
    | FontColor =>
      match self.font {
        Some(font) => { ..self, font: normalize_font(font.without(attr)) }
        None => self
      }
    AlignHorizontal | AlignVertical | AlignWrap =>
      match self.align {
        Some(align) => { ..self, align: normalize_align(align.without(attr)) }
        None => self
      }
    BorderLeft | BorderRight | BorderTop | BorderBottom =>
      match self.borders {
        Some(borders) =>
          { ..self, borders: normalize_borders(borders.without(attr)) }
        None => self
      }
    ProtectionLocked | ProtectionHidden =>
      match self.protection {
        Some(protection) =>
          { ..self, protection: normalize_protection(protection.without(attr)) }
        None => self
      }
  }
  { ..dropped, cleared: dropped.cleared.adding(attr) }
}

///|
/// The style as it is finally worn, with the record of what it cleared dropped.
///
/// Layering is over by the time a style reaches the emitter, and an attribute
/// that was explicitly not set is then indistinguishable from one nobody
/// mentioned — Excel has one way to write both. Dropping the set here is what
/// keeps two styles that differ only in how they arrived at the same look from
/// interning as two `cellXfs` ids (ADR-004).
pub fn Style::settled(self : Style) -> Style {
  { ..self, cleared: StyleAttrs::none() }
}

///|
/// Lay `self` over `base`: every attribute `self` sets wins, every attribute it
/// clears is taken away, and everything it does not mention shows through from
/// `base`. This is what one style inheriting another means — a `header` that
/// extends a `base` adds bold without restating the face and size — and it is
/// also how a column or row band reaches a cell (`docs/spec.md` §4).
///
/// The merge reaches *inside* a font, an alignment, and the four border edges,
/// so setting `font: { bold: true }` over a base font keeps the base's size.
/// A fill and a number format are single values with no parts to merge, so
/// setting either replaces it outright.
pub fn Style::over(self : Style, base : Style) -> Style {
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
    protection: merge_protection(base.protection, self.protection, self.cleared),
    cleared: self.cleared.union(base.cleared).except(self.assigned()),
  }
}

///|
/// What a band actually passes down to a cell holding `value`.
///
/// Everything a band sets reaches every cell — except a **number format landing
/// on text**, which Excel ignores unless the format carries a fourth, text
/// section (ECMA-376 §18.8.31: a format is `positive;negative;zero;text`). So
/// dropping it here is not a house rule, it is Excel's; inheriting it anyway
/// would cost a style id to change nothing.
///
/// It would also do harm. The Excel backend renders such a cell by applying the
/// *numeric* section to the text, so a `Revenue` header under a `#,##0` column
/// reads back as the literal `#,##0` — and a pivot, which finds its fields by
/// reading that header, then cannot find them.
///
/// A `format:` written on the cell itself is untouched: that is a request, not
/// an inheritance.
pub fn Style::inherited_by(self : Style, value : CellValue) -> Style {
  guard value is (Text(_) | RichText(_)) else { return self }
  guard self.number_format is Some(code) && !has_text_section(code) else {
    return self
  }
  { ..self, number_format: None }
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
/// A font laid over another, attribute by attribute, with the overriding
/// style's cleared attributes taken away. Part of `Style::over`; callers merge
/// whole styles, not their pieces. The same shape serves the alignment, the
/// borders, and the protection below.
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
/// One font attribute dropped, leaving the rest.
fn Font::without(self : Font, attr : StyleAttr) -> Font {
  match attr {
    FontBold => { ..self, bold: None }
    FontItalic => { ..self, italic: None }
    FontUnderline => { ..self, underline: None }
    FontStrike => { ..self, strike: None }
    FontSize => { ..self, size: None }
    FontName => { ..self, name: None }
    FontColor => { ..self, color: None }
    _ => self
  }
}

///|
fn Alignment::without(self : Alignment, attr : StyleAttr) -> Alignment {
  match attr {
    AlignHorizontal => { ..self, horizontal: None }
    AlignVertical => { ..self, vertical: None }
    AlignWrap => { ..self, wrap: None }
    _ => self
  }
}

///|
fn Borders::without(self : Borders, attr : StyleAttr) -> Borders {
  match attr {
    BorderLeft => { ..self, left: None }
    BorderRight => { ..self, right: None }
    BorderTop => { ..self, top: None }
    BorderBottom => { ..self, bottom: None }
    _ => self
  }
}

///|
fn CellProtection::without(
  self : CellProtection,
  attr : StyleAttr,
) -> CellProtection {
  match attr {
    ProtectionLocked => { ..self, locked: None }
    ProtectionHidden => { ..self, hidden: None }
    _ => self
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
/// The empty alignment — Excel's own placement, whatever that is for the cell.
pub fn Alignment::empty() -> Alignment {
  { horizontal: None, vertical: None, wrap: None }
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
  { left: None, right: None, top: None, bottom: None }
}

///|
/// The protection that changes nothing — Excel's defaults on both counts.
pub fn CellProtection::empty() -> CellProtection {
  { locked: None, hidden: None }
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
