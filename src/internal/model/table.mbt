///|
/// A table over a range whose top row is the header, so at least two rows.
/// `None` keeps Excel's `TableN` name and the backend's `TableStyleMedium9`.
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
/// Excel's built-in table styles as (family, count). Anything else is refused,
/// since Excel silently falls back on a name it does not know.
pub let table_style_families : Array[(String, Int32)] = [
  ("TableStyleLight", 21),
  ("TableStyleMedium", 28),
  ("TableStyleDark", 11),
]
