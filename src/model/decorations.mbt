// Things layered *over* cells rather than held *in* them: data validation, an
// auto filter, and hyperlinks. Each names a cell or a range and adds behaviour
// there — the cell's own value and style are unaffected, and a decoration on an
// empty cell is legal (if rarely useful).
//
// They share a file because each is small on its own; they share nothing else.

///|
/// A range that may name a sheet other than the one holding it: `A1:B9` on this
/// sheet, `Lists!A1:A9` on another. A validation list is routinely sourced from
/// a lookup sheet, which a bare `CellRange` could not express.
///
/// `sheet` is `None` for the sheet the reference was written on.
pub(all) struct SheetRange {
  sheet : String?
  range : CellRange
} derive(Eq, Debug)

///|
/// What a data validation accepts. Excel calls this the "Allow" setting.
pub(all) enum ValidationRule {
  /// A drop-down of literal choices, in the order given.
  List(Array[String])
  /// A drop-down whose choices are read from cells.
  ListFrom(SheetRange)
  /// A value of `kind` that must satisfy `check`.
  Compare(kind~ : ValidationKind, check~ : Comparison)
} derive(Eq, Debug)

///|
/// The kind of value a comparing validation measures: a whole number, any
/// number, the *length* of the text, or a date (ECMA-376 §18.18.20,
/// `ST_DataValidationType`).
pub(all) enum ValidationKind {
  Whole
  Decimal
  TextLength
  DateValue
} derive(Eq, Debug)

///|
/// One endpoint of a validation test. A date stays a `DateTime` rather than
/// becoming a number here because the serial depends on the workbook's epoch,
/// which only the emitter knows.
pub(all) enum Bound {
  Number(Double)
  Date(@units.DateTime)
} derive(Eq, Debug)

///|
/// The test a value must pass (ECMA-376 §18.18.15, `ST_DataValidationOperator`).
/// The two-endpoint forms take their bounds in the order written.
pub(all) enum Comparison {
  Between(Bound, Bound)
  NotBetween(Bound, Bound)
  Equal(Bound)
  NotEqual(Bound)
  AtLeast(Bound)
  AtMost(Bound)
  GreaterThan(Bound)
  LessThan(Bound)
} derive(Eq, Debug)

///|
/// The pop-up Excel shows when the cell is selected: a title and a body.
pub(all) struct ValidationPrompt {
  title : String
  body : String
} derive(Eq, Debug)

///|
/// What Excel does about a value the rule rejects: which dialog to show, and
/// what it says. Without one, Excel accepts the value silently.
pub(all) struct ValidationError {
  title : String
  body : String
  style : ValidationErrorStyle
} derive(Eq, Debug)

///|
/// How hard Excel pushes back on a rejected value (ECMA-376 §18.18.18): `Stop`
/// refuses it, `Warning` and `Information` let the user keep it.
pub(all) enum ValidationErrorStyle {
  Stop
  Warning
  Information
} derive(Eq, Debug)

///|
/// A data validation over a range: what it accepts, whether an empty cell is
/// allowed, and the messages shown on selection and on rejection.
pub(all) struct Validation {
  at : CellRange
  rule : ValidationRule
  /// `true` lets the cell be left empty — Excel's "Ignore blank".
  allow_blank : Bool
  prompt : ValidationPrompt?
  error : ValidationError?
} derive(Eq, Debug)

///|
/// Excel's limit on a validation formula, which for an inline drop-down is the
/// comma-joined list of choices. Exceeding it is rejected with a diagnostic
/// rather than being passed to the backend, which would fail far from the spec.
pub let max_validation_list_length : Int = 255

///|
/// Where a hyperlink goes.
///
/// A `Location` stays text because it is not always a cell range: Excel accepts
/// a defined name there as readily as `Summary!A1`, and narrowing it to a range
/// would reject a legal spec.
pub(all) enum LinkTarget {
  /// Somewhere outside the workbook — a URL, or a `mailto:`/`file:` target.
  Url(String)
  /// Somewhere inside the workbook: `Summary!A1`, or a defined name.
  Location(String)
} derive(Eq, Debug)

///|
/// A hyperlink on one cell, with an optional hover tooltip.
///
/// A link does not give the cell its text — Excel displays the cell's own value
/// — so a linked cell is normally written in `cells:` as well.
pub(all) struct Link {
  at : @units.CellRef
  target : LinkTarget
  tip : String?
} derive(Eq, Debug)
