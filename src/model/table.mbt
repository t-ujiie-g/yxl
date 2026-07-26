// Excel *tables* (ListObjects, ECMA-376 §18.5): a range declared to be one
// thing — a header row over rows of data — rather than a grid that happens to
// look like one. Excel gives a table its own name, filter buttons, banded
// shading, and structured references (`=SUM(Sales[Amount])`), and extends all of
// them over any row typed beneath it.
//
// The cells themselves are written as usual; a table only says what the region
// *is*.

///|
/// A table over a range. The range's top row is its header — the column names —
/// and every row below is data, so a table spans at least two rows.
pub(all) struct Table {
  at : CellRange
  /// The name a formula refers to the table by. `None` leaves Excel to name it
  /// `Table1`, `Table2`, … — fine for a table nothing refers to.
  name : String?
  /// One of Excel's built-in table styles; `None` keeps the backend's default,
  /// `TableStyleMedium9`.
  style : String?
  /// The four appearance toggles of Excel's "Table Design" ribbon: shade
  /// alternate rows, shade alternate columns, and emphasize the first or last
  /// column. What each does depends on the style, which supplies the colors.
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

///|
/// Whether `name` is one of Excel's built-in table styles.
pub fn is_table_style(name : String) -> Bool {
  table_styles.contains(name)
}

///|
/// The families spelled out, so a lookup is a comparison rather than a parse.
let table_styles : Array[String] = numbered_styles(table_style_families)

///|
/// Every name a family list stands for: `("TableStyleDark", 11)` spells out
/// `TableStyleDark1` … `TableStyleDark11`. Excel numbers its built-in styles
/// this way for tables and pivot tables alike.
fn numbered_styles(families : Array[(String, Int)]) -> Array[String] {
  let names = []
  for family in families {
    let (prefix, count) = family
    for number in 1..<=count {
      names.push("\{prefix}\{number}")
    }
  }
  names
}
