///|
/// An RGB(A) colour as canonical uppercase hex, `RRGGBB` or `AARRGGBB`. Writers
/// ask for `argb` (SpreadsheetML) or `rgb` (DrawingML) by name, since the wrong
/// width is invalid; `hex` is for people.
pub struct Color(String) derive(Eq, Hash, Debug)

///|
/// Parse a hex color: an optional leading `#`, then exactly 6 (`RRGGBB`) or 8
/// (`AARRGGBB`) hex digits, case-insensitive. Returns `None` otherwise; the
/// caller turns that into a domain diagnostic.
pub fn Color::parse(text : String) -> Color? {
  let body = if text.has_prefix("#") { text[1:] } else { text[:] }
  guard body.length() is (6 | 8) else { return None }
  let out = StringBuilder()
  for ch in body {
    guard ch is ('0'..<='9' | 'A'..<='F' | 'a'..<='f') else { return None }
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
/// The `RRGGBB` half alone, as DrawingML's `ST_HexColorRGB` (ECMA-376
/// §20.1.10.42) and the legacy palette's `00RRGGBB` both need.
pub fn Color::rgb(self : Color) -> String {
  if self.0.length() == 8 {
    self.0[2:].to_owned()
  } else {
    self.0
  }
}
