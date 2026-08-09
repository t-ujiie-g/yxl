///|
/// A table over a range. The range's top row is its header — the column names —
/// and every row below is data, so a table spans at least two rows.
///
/// `name` is what a formula refers to the table by; `None` leaves Excel to name
/// it `Table1`, `Table2`, …, which is fine for a table nothing refers to.
/// `style` is one of Excel's built-in table styles, `None` keeping the
/// backend's `TableStyleMedium9`.
///
/// The four booleans are the appearance toggles of Excel's "Table Design"
/// ribbon. What each does depends on the style, which supplies the colours.
pub(all) struct Table {
  at : CellRange
  name : String?
  style : String?
  banded_rows : Bool
  banded_columns : Bool
  first_column : Bool
  last_column : Bool
} derive(Eq, Debug)

///|
/// Excel's built-in table styles, as the families it groups them into and how
/// many are numbered within each: `TableStyleLight1` … `TableStyleLight21`, and
/// so on. A style outside them is rejected with a diagnostic rather than written
/// through, since Excel silently falls back to its default for a name it does
/// not know (ADR-006).
pub let table_style_families : Array[(String, Int)] = [
  ("TableStyleLight", 21),
  ("TableStyleMedium", 28),
  ("TableStyleDark", 11),
]
