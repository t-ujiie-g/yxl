///|
/// A 1-based cell reference — column and row, where (1, 1) is `A1`. Stored as
/// numbers rather than an A1 string so the model stays backend-agnostic and
/// range/offset arithmetic is possible; `to_a1` renders the Excel form. Using a
/// newtype here, rather than a bare `String`, keeps cell references type-safe at
/// internal API boundaries.
pub struct CellRef {
  col : Int
  row : Int
} derive(Eq, Debug)

///|
/// Build a reference from a 1-based column and row. Both are expected to be
/// `>= 1`; a reference derived from user input is validated where it is parsed
/// (a bad ref becomes a `SchemaError` in the loader), not here.
pub fn CellRef::new(col~ : Int, row~ : Int) -> CellRef {
  { col, row }
}

///|
/// Parse an A1-style reference: `A1` -> (1, 1), `AA10` -> (27, 10). Returns
/// `None` for anything that is not `<letters><digits>` with both parts present
/// and the row `>= 1` (e.g. `A0`, `1A`, `A`, `""`). The caller turns `None` into
/// a domain diagnostic. The inverse of `to_a1`.
pub fn CellRef::parse_a1(text : String) -> CellRef? {
  let chars = text.to_array()
  let mut i = 0
  let mut col = 0
  while i < chars.length() && chars[i] is ('A'..='Z' as ch) {
    col = col * 26 + (ch.to_int() - 65 + 1)
    i = i + 1
  }
  // Need at least one letter and at least one following digit.
  if i == 0 || i == chars.length() {
    return None
  }
  let mut row = 0
  while i < chars.length() {
    guard chars[i] is ('0'..='9' as ch) else { return None }
    row = row * 10 + (ch.to_int() - 48)
    i = i + 1
  }
  if row < 1 {
    None
  } else {
    Some({ col, row })
  }
}

///|
/// Render as an A1-style reference: (1, 1) -> `A1`, (27, 10) -> `AA10`. The
/// column uses Excel's bijective base-26 encoding (A..Z, AA..AZ, ...).
pub fn CellRef::to_a1(self : CellRef) -> String {
  // Column letters come out least-significant first, so collect and reverse.
  let letters : Array[Char] = []
  let mut n = self.col
  while n > 0 {
    let rem = (n - 1) % 26
    letters.push((65 + rem).to_char().unwrap())
    n = (n - 1) / 26
  }
  let sb = StringBuilder::new()
  for i = letters.length() - 1; i >= 0; i = i - 1 {
    sb.write_char(letters[i])
  }
  sb.write_string(self.row.to_string())
  sb.to_string()
}
