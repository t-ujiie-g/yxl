///|
/// A 1-based cell reference — column and row, where (1, 1) is `A1`. Stored as
/// numbers rather than an A1 string so the model stays backend-agnostic and
/// range/offset arithmetic is possible; `to_a1` renders the Excel form. Using a
/// newtype here (not a bare `String`) is the type-safe-boundary rule (AGENTS §7).
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
