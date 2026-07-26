// Pivot tables: a summary of a region of cells, grouped down the rows and along
// the columns and aggregated in the middle. Like a chart, a pivot holds no
// values of its own — it names the region it summarizes, and Excel does the
// summarizing, refreshing the whole thing whenever the source changes.

///|
/// A pivot table placed on a sheet.
///
/// Excel's fourth axis — the "Filters" box above the pivot — is missing because
/// the Excel backend cannot yet write one Excel will open: the `<location>` it
/// emits does not account for the filter rows above the body, and Excel answers
/// with `#SPILL!` (moonbitlang/office.mbt#264). The loader refuses `filters:` by
/// name and says why.
pub(all) struct Pivot {
  /// Where the pivot is drawn. Excel grows it past this range as it needs to,
  /// so this is the corner it starts from rather than a promise about its size.
  at : CellRange
  /// The cells summarized, header row first — the column names there are the
  /// field names every axis below refers to. May name another sheet, which is
  /// the usual arrangement: raw data on one tab, the summary on another.
  source : SheetRange
  /// The fields grouped down the side and along the top.
  rows : Array[PivotField]
  columns : Array[PivotField]
  /// The fields aggregated in the body, each with the function to aggregate by.
  values : Array[PivotValue]
  /// What formulas and the field list call this pivot; `None` leaves Excel to
  /// name it `PivotTable1`, `PivotTable2`, …
  name : String?
  /// One of Excel's built-in pivot styles; `None` keeps the backend's default,
  /// `PivotStyleLight16`.
  style : String?
  /// The totals down the right edge and along the bottom, both of which Excel
  /// shows by default.
  row_grand_totals : Bool
  column_grand_totals : Bool
} derive(Eq, Debug)

///|
/// A field on one of the grouping axes: which source column, and what to call it
/// in the pivot if not by its own name.
pub(all) struct PivotField {
  field : String
  name : String?
} derive(Eq, Debug)

///|
/// A field in the body: which source column, how to aggregate it, and what to
/// call the result. `None` leaves Excel's own wording — "Sum of Revenue".
pub(all) struct PivotValue {
  field : String
  function : PivotFunction
  name : String?
} derive(Eq, Debug)

///|
/// How a value field is aggregated (ECMA-376 §18.18.17, `ST_DataConsolidateFunction`).
/// Excel's full list is longer; these are the ones its own "Summarize Values By"
/// menu offers.
pub(all) enum PivotFunction {
  Sum
  Count
  CountNumbers
  Average
  Max
  Min
  Product
  StdDev
  StdDevP
  Var
  VarP
} derive(Eq, Debug)

///|
/// Excel's built-in pivot styles, in the same shape as the table ones: three
/// families of twenty-eight. Checked here rather than passed through, since
/// Excel falls back to its default for a name it does not know (ADR-006).
pub let pivot_style_families : Array[(String, Int)] = [
  ("PivotStyleLight", 28),
  ("PivotStyleMedium", 28),
  ("PivotStyleDark", 28),
]

///|
/// Whether `name` is one of Excel's built-in pivot styles.
pub fn is_pivot_style(name : String) -> Bool {
  pivot_styles.contains(name)
}

///|
let pivot_styles : Array[String] = numbered_styles(pivot_style_families)
