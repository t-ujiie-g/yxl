///|
/// An RGB(A) color, stored as canonical uppercase hex without a leading `#`
/// (either `RRGGBB` or `AARRGGBB`). A newtype rather than a bare `String` so a
/// color cannot be confused with any other text at an internal API boundary.
/// Construct through `parse`, which rejects anything that is not 6 or 8 hex
/// digits.
///
/// Excel has **two** color attribute types and they are not interchangeable:
/// SpreadsheetML writes four bytes (`ST_UnsignedIntHex`, `AARRGGBB` — a tab
/// color, a font color, a conditional format's color) and DrawingML writes
/// three (`ST_HexColorRGB`, `RRGGBB` — a shape's fill and outline). A value of
/// the wrong width is a schema violation Excel answers with its repair dialog,
/// so a caller writing into a workbook asks for `argb` or `rgb` by name rather
/// than passing `hex` through and hoping. `hex` is for showing the color back
/// to a human — a spec, a diagnostic — where the author's own spelling is the
/// right one to keep.
pub struct Color(String) derive(Eq, Hash, Debug)

///|
/// Parse a hex color: an optional leading `#`, then exactly 6 (`RRGGBB`) or 8
/// (`AARRGGBB`) hex digits, case-insensitive. Returns `None` otherwise; the
/// caller turns that into a domain diagnostic.
pub fn Color::parse(text : String) -> Color? {
  let body = if text.has_prefix("#") { text[1:] } else { text[:] }
  guard body.length() is (6 | 8) else { return None }
  let out = StringBuilder::new()
  for ch in body {
    guard ch is ('0'..='9' | 'A'..='F' | 'a'..='f') else { return None }
    // `to_ascii_uppercase` leaves digits and `A`..`F` unchanged.
    out.write_char(ch.to_ascii_uppercase())
  }
  Some(Color(out.to_string()))
}

///|
/// The canonical uppercase hex digits as written, without a leading `#` — 6 or
/// 8 of them, whichever the color was parsed from.
pub fn Color::hex(self : Color) -> String {
  self.0
}

///|
/// The `AARRGGBB` form SpreadsheetML's color attributes take
/// (`ST_UnsignedIntHex`, ECMA-376 §18.18.86), opaque where the color carries no
/// alpha of its own.
pub fn Color::argb(self : Color) -> String {
  if self.0.length() == 6 {
    "FF" + self.0
  } else {
    self.0
  }
}

///|
/// The `RRGGBB` half alone, dropping an alpha byte where the colour carries one.
///
/// Two callers need exactly three bytes. DrawingML's `ST_HexColorRGB`
/// (ECMA-376 §20.1.10.42) is the one that ends up in a file — a shape's fill
/// and outline — and Excel's legacy palette is the other: it writes its entries
/// as `00RRGGBB`, an alpha byte it does not mean, since a fully transparent
/// palette would paint nothing.
pub fn Color::rgb(self : Color) -> String {
  if self.0.length() == 8 {
    self.0[2:].to_owned()
  } else {
    self.0
  }
}
