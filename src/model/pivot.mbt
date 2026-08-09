///|
/// A pivot table placed on a sheet.
///
/// Excel's fourth axis — the "Filters" box above the pivot — is missing because
/// the Excel backend cannot yet write one Excel will open: the `<location>` it
/// emits does not account for the filter rows above the body, and Excel answers
/// with `#SPILL!` (moonbitlang/office.mbt#264). The loader refuses `filters:` by
/// name and says why.
///
/// - `at` — where the pivot starts. Excel grows it past this range as it needs
///   to, so it is a corner rather than a promise about the size.
/// - `source` — the cells summarized, header row first: the column names there
///   are the field names every axis refers to. May name another sheet, which is
///   the usual arrangement — raw data on one tab, the summary on another.
/// - `rows`, `columns` — the fields grouped down the side and along the top.
/// - `values` — the fields aggregated in the body, each with its function.
/// - `name` — what formulas and the field list call this pivot; `None` leaves
///   Excel to name it `PivotTable1`, `PivotTable2`, …
/// - `style` — one of Excel's built-in pivot styles; `None` keeps the backend's
///   default, `PivotStyleLight16`.
/// - the grand totals down the right edge and along the bottom, both of which
///   Excel shows by default.
pub(all) struct Pivot {
  at : CellRange
  source : SheetRange
  rows : Array[PivotField]
  columns : Array[PivotField]
  values : Array[PivotValue]
  name : String?
  style : String?
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
