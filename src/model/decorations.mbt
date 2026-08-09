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
/// One endpoint of a comparison. A date stays a `DateTime` rather than becoming
/// a number here because the serial depends on the workbook's epoch, which only
/// the emitter knows.
///
/// `Text` is reachable from a conditional format (`cell: { "=": Paid }`) but not
/// from a validation, whose kind already fixes what its bounds may be.
pub(all) enum Bound {
  Number(Double)
  Date(@units.DateTime)
  Text(String)
} derive(Eq, Debug)

///|
/// The test a value must pass (ECMA-376 §18.18.15, `ST_DataValidationOperator`;
/// the same eight serve a conditional format's `cellIs` rule). The two-endpoint
/// forms take their bounds in the order written.
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
/// How a conditional format decides which cells it applies to (ECMA-376
/// §18.18.12, `ST_CfType`).
///
/// The first group *highlights*: a matching cell is drawn in the format's style,
/// and a format carrying one of these without a style would do nothing visible.
/// The last three *draw* instead — a gradient, a bar, or an icon per cell — and
/// carry their own appearance, so a style would have nothing to apply.
pub(all) enum ConditionalRule {
  /// The cell's value against a bound: `cellIs`.
  CellIs(Comparison)
  /// A formula evaluated per cell, matching where it is true: `expression`.
  /// Written relative to the range's top-left cell, as Excel's own dialog does.
  Formula(String)
  /// The cell's text against a substring: `containsText` and its relatives.
  Text(match_~ : TextMatch, value~ : String)
  /// The highest (or, with `bottom`, lowest) `rank` cells, or that percentage of
  /// them: `top10`.
  Rank(count~ : Int, bottom~ : Bool, percent~ : Bool)
  /// Cells whose value appears more than once in the range: `duplicateValues`.
  Duplicate
  /// Cells whose value appears exactly once: `uniqueValues`.
  Unique
  /// A two- or three-color gradient across the range: `colorScale`.
  ColorScale(low~ : @units.Color, middle~ : @units.Color?, high~ : @units.Color)
  /// A bar in each cell, in proportion to its value: `dataBar`.
  DataBar(color~ : @units.Color, bar_only~ : Bool)
  /// An icon per cell, chosen by which band its value falls in: `iconSet`.
  IconSet(style~ : String, reverse~ : Bool, icons_only~ : Bool)
} derive(Eq, Debug)

///|
/// Which part of the cell's text a `Text` rule looks at.
pub(all) enum TextMatch {
  Contains
  NotContains
  BeginsWith
  EndsWith
} derive(Eq, Debug)

///|
/// The icon sets Excel knows, by the names OOXML gives them (ECMA-376
/// §18.18.42, `ST_IconSetType`). Excel's own vocabulary is used verbatim rather
/// than translated, so a spec names the same thing its documentation does.
///
/// These are the seventeen the *base* schema's enumeration admits. Excel 2010
/// added three more, which are a different matter — see
/// `unwritable_icon_set_styles`.
pub let icon_set_styles : Array[String] = [
  "3Arrows", "3ArrowsGray", "3Flags", "3Signs", "3Symbols", "3Symbols2", "3TrafficLights1",
  "3TrafficLights2", "4Arrows", "4ArrowsGray", "4Rating", "4RedToBlack", "4TrafficLights",
  "5Arrows", "5ArrowsGray", "5Quarters", "5Rating",
]

///|
/// Icon sets Excel offers and the backend cannot write: added in Excel 2010,
/// they live only in the `x14` extension schema, and the backend puts the name
/// straight into the base `<iconSet iconSet="…">` attribute — whose enumeration
/// (ECMA-376 §18.18.42) has seventeen values and none of these. A workbook
/// naming one is schema-invalid and Excel offers to repair it.
///
/// Refused by name, with the reason, until that is fixed upstream
/// (moonbitlang/office.mbt#403) — the same arrangement as the camel-case shape
/// presets. The backend accepts all twenty, so this list cannot be derived from
/// it: trusting the backend's acceptance for the set of legal values is what
/// let these ship in the first place.
pub let unwritable_icon_set_styles : Array[String] = [
  "3Stars", "3Triangles", "5Boxes",
]

///|
/// Excel's cap on a `Rank` rule by count, as its own dialog enforces it.
pub let max_rank_count : Int = 1000

///|
/// Excel's cap on a `Rank` rule by percentage.
pub let max_rank_percent : Int = 100

///|
/// A conditional format over a range: what decides it, and how a matching cell
/// is drawn.
pub(all) struct ConditionalFormat {
  at : CellRange
  rule : ConditionalRule
  /// The look applied where the rule matches. Excel keeps these in their own
  /// table (`dxfs`) rather than `cellXfs`, and only the parts it sets are
  /// overridden — a rule that sets a fill leaves the cell's font alone.
  style : Style?
  /// `true` stops Excel evaluating any later rule on a cell this one matched.
  stop_if_true : Bool
} derive(Eq, Debug)

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
/// A note attached to a cell — what Excel now calls a *note* and older versions
/// called a comment: a box that appears on hover, with the author's name above
/// the text.
pub(all) struct Comment {
  at : @units.CellRef
  text : String
  /// Shown above the text, as Excel writes the name of whoever typed it. A
  /// note always carries one in the file, so `None` does not omit it — it
  /// leaves the backend to write its generic default.
  author : String?
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
