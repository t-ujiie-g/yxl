///|
/// A pivot table. `at` is a corner Excel grows from; `source`'s header row names
/// the fields the axes refer to. `None` keeps Excel's name and the backend's
/// `PivotStyleLight16`.
pub(all) struct Pivot {
  at : CellRange
  source : SheetRange
  rows : Array[PivotField]
  columns : Array[PivotField]
  filters : Array[PivotField]
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
pub let pivot_style_families : Array[(String, Int32)] = [
  ("PivotStyleLight", 28),
  ("PivotStyleMedium", 28),
  ("PivotStyleDark", 28),
]
