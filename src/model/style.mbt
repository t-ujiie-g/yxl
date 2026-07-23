///|
/// A cell's visual style: any combination of a font, a solid fill, borders, an
/// alignment, and an Excel number-format code. Every field is optional; `None`
/// throughout is the default (`General`) style. Styles are compared and hashed
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
} derive(Eq, Hash, Debug)

///|
/// The empty style — every attribute defaulted. Equal to a `Style` with all
/// `None` fields, so it interns with any other empty style.
pub fn Style::empty() -> Style {
  { font: None, fill: None, borders: None, align: None, number_format: None }
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
