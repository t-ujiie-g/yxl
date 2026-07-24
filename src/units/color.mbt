///|
/// An RGB(A) color, stored as canonical uppercase hex without a leading `#`
/// (either `RRGGBB` or `AARRGGBB`). A newtype rather than a bare `String` so a
/// color cannot be confused with any other text at an internal API boundary;
/// `hex` renders the form the Excel backend expects. Construct through `parse`,
/// which rejects anything that is not 6 or 8 hex digits.
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
/// The canonical uppercase hex digits, without a leading `#`.
pub fn Color::hex(self : Color) -> String {
  self.0
}
