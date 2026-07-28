///|
/// A cell's style: any combination of a font, a solid fill, borders, an
/// alignment, an Excel number-format code, and what sheet protection does to
/// the cell. Every field is optional; `None` throughout is the default
/// (`General`) style. Styles are compared and hashed
/// structurally so the emitter can intern identical styles to a single Excel
/// `cellXfs` id (ADR-004) — declare a look once, reference it many times, emit
/// it once.
pub(all) struct Style {
  font : Font?
  fill : Fill?
  borders : Borders?
  align : Alignment?
  /// An Excel number-format code, e.g. `"#,##0.00"` or `"0%"`. A number format
  /// is part of the style (not a separate cell attribute) so it interns with
  /// the rest of the look.
  number_format : String?
  /// What sheet protection does to a cell wearing this style. Excel keeps this
  /// in the style rather than on the cell, so it interns with the rest.
  protection : CellProtection?
} derive(Eq, Hash, Debug)

///|
/// A cell's half of sheet protection — Excel's Format Cells → Protection tab.
/// Neither field does anything until the sheet is protected.
///
/// Excel locks every cell by default, so protecting a sheet freezes all of it;
/// the way to leave a form's input boxes editable is to give *them* a style
/// with `locked: false`.
pub(all) struct CellProtection {
  /// `false` lets a protected sheet's cell still be edited.
  locked : Bool?
  /// `true` hides the cell's formula from the formula bar while protected. The
  /// value still shows, and the file still contains the formula.
  hidden : Bool?
} derive(Eq, Hash, Debug)

///|
/// Lay `self` over `base`, field by field.
fn CellProtection::over(
  self : CellProtection,
  base : CellProtection,
) -> CellProtection {
  {
    locked: or_else(base.locked, self.locked),
    hidden: or_else(base.hidden, self.hidden),
  }
}

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
  }
}

///|
/// A style carrying only a number-format code — the common shorthand.
pub fn Style::number_format(code : String) -> Style {
  { ..Style::empty(), number_format: Some(code) }
}

///|
/// Whether the style sets nothing (equal to `empty`). Such a style needs no
/// `cellXfs` entry; the emitter leaves the cell on the default style.
pub fn Style::is_empty(self : Style) -> Bool {
  self == Style::empty()
}

///|
/// Lay `self` over `base`: every attribute `self` sets wins, and everything it
/// leaves unset shows through from `base`. This is what one style inheriting
/// another means — a `header` that extends a `base` adds bold without restating
/// the face and size.
///
/// The merge reaches *inside* a font, an alignment, and the four border edges,
/// so setting `font: { bold: true }` over a base font keeps the base's size.
/// A fill and a number format are single values with no parts to merge, so
/// setting either replaces it outright.
pub fn Style::over(self : Style, base : Style) -> Style {
  {
    font: merge_option(base.font, self.font, Font::over),
    align: merge_option(base.align, self.align, Alignment::over),
    borders: merge_option(base.borders, self.borders, Borders::over),
    fill: or_else(base.fill, self.fill),
    number_format: or_else(base.number_format, self.number_format),
    protection: merge_option(
      base.protection,
      self.protection,
      CellProtection::over,
    ),
  }
}

///|
/// `over` if both sides are set, otherwise whichever one is.
fn[T] merge_option(base : T?, over : T?, merge : (T, T) -> T) -> T? {
  match (base, over) {
    (Some(base), Some(over)) => Some(merge(over, base))
    (None, over) => over
    (base, None) => base
  }
}

///|
/// The overriding value if set, else the base's.
fn[T] or_else(base : T?, over : T?) -> T? {
  match over {
    Some(_) => over
    None => base
  }
}

///|
/// A font laid over another, attribute by attribute. Part of `Style::over`;
/// callers merge whole styles, not their pieces.
fn Font::over(self : Font, base : Font) -> Font {
  {
    bold: or_else(base.bold, self.bold),
    italic: or_else(base.italic, self.italic),
    underline: or_else(base.underline, self.underline),
    strike: or_else(base.strike, self.strike),
    size: or_else(base.size, self.size),
    name: or_else(base.name, self.name),
    color: or_else(base.color, self.color),
  }
}

///|
/// An alignment laid over another, attribute by attribute.
fn Alignment::over(self : Alignment, base : Alignment) -> Alignment {
  {
    horizontal: or_else(base.horizontal, self.horizontal),
    vertical: or_else(base.vertical, self.vertical),
    wrap: or_else(base.wrap, self.wrap),
  }
}

///|
/// Borders laid over others, edge by edge; an edge the overriding style sets
/// replaces that edge whole (a `Border` is a style plus a color, not parts to
/// blend).
fn Borders::over(self : Borders, base : Borders) -> Borders {
  {
    left: or_else(base.left, self.left),
    right: or_else(base.right, self.right),
    top: or_else(base.top, self.top),
    bottom: or_else(base.bottom, self.bottom),
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
