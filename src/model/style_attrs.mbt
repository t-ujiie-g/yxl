///|
/// One leaf of a style — every attribute a spec can set, at the granularity
/// layering works on (`docs/spec.md` §6).
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
/// A set of style attributes, as a bitmask. A bitmask rather than a collection
/// so a `Style` carrying one still compares and hashes structurally, which is
/// what lets the emitter intern styles (ADR-004).
pub struct StyleAttrs(UInt) derive(Eq, Hash, Debug)

///|
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
/// The empty set.
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
/// This style, also clearing `attrs` — except any it gives a value to, since a
/// value written beside a `null` wins (`docs/spec.md` §6).
pub fn Style::clearing(self : Style, attrs : StyleAttrs) -> Style {
  { ..self, cleared: self.cleared.union(attrs).except(self.assigned()) }
}

///|
/// The style as it is finally worn, with the record of what it cleared dropped.
///
/// Once layering is over, an attribute explicitly not set is indistinguishable
/// from one nobody mentioned — Excel writes both the same way — and dropping the
/// record is what keeps the two from interning as two `cellXfs` ids (ADR-004).
pub fn Style::settled(self : Style) -> Style {
  { ..self, cleared: StyleAttrs::none() }
}
