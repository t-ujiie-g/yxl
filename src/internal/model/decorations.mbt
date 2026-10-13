///|
/// A range that may name another sheet (`Lists!A1:A9`), as a validation list
/// sourced from a lookup sheet does. `sheet` is `None` for the writing sheet.
pub(all) struct SheetRange {
  sheet : String?
  range : CellRange
} derive(Eq, Debug)

///|
/// Split `Sheet!A1:B9` on Excel's quoting rules, where `''` inside `'...'` is
/// one apostrophe; `None` if a quoted name never closes. Shared by the loader
/// and the reader so a sheet named `It's data` survives the round trip.
pub fn split_sheet_prefix(text : String) -> (String?, String)? {
  let chars = text.iter().to_array()
  guard chars.length() > 0 && chars[0] == '\'' else {
    // Unquoted: Excel requires quotes around any sheet name that could be
    // confused for something else, so the first `!` is the separator.
    return match text.split_once("!") {
      Some((sheet, rest)) => Some((Some(sheet.to_owned()), rest.to_owned()))
      None => Some((None, text))
    }
  }
  let name = StringBuilder()
  let mut index = 1
  while index < chars.length() {
    if chars[index] == '\'' {
      if index + 1 < chars.length() && chars[index + 1] == '\'' {
        name.write_char('\'')
        index += 2
        continue
      }
      break
    }
    name.write_char(chars[index])
    index += 1
  }
  // `index` is at the closing quote, which must be followed by `!range`.
  guard index + 1 < chars.length() &&
    chars[index] == '\'' &&
    chars[index + 1] == '!' else {
    return None
  }
  let rest = StringBuilder()
  for taken in (index + 2)..<chars.length() {
    rest.write_char(chars[taken])
  }
  Some((Some(name.to_string()), rest.to_string()))
}

///|
/// What a data validation accepts. Excel calls this the "Allow" setting. A
/// `List`'s choices are offered in the order given.
pub(all) enum ValidationRule {
  List(Array[String])
  ListFrom(SheetRange)
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
/// One endpoint of a comparison. A date stays a `DateTime` because its serial
/// depends on the workbook's epoch, which only the emitter knows.
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
/// allowed (Excel's "Ignore blank"), and the messages shown on selection and on
/// rejection.
pub(all) struct Validation {
  at : CellRange
  rule : ValidationRule
  allow_blank : Bool
  prompt : ValidationPrompt?
  error : ValidationError?
} derive(Eq, Debug)

///|
/// Excel's limit on a validation formula, which for an inline drop-down is the
/// comma-joined list of choices. Exceeding it is rejected with a diagnostic
/// rather than being passed to the backend, which would fail far from the spec.
pub let max_validation_list_length : Int32 = 255

///|
/// How a conditional format picks its cells (ECMA-376 §18.18.12). The last three
/// draw their own appearance and take no style; a `Formula` is relative to the
/// range's top-left.
pub(all) enum ConditionalRule {
  /// The cell's value against a bound: `cellIs`.
  CellIs(Comparison)
  /// A formula evaluated per cell, matching where it is true: `expression`.
  Formula(String)
  /// The cell's text against a substring: `containsText` and its relatives.
  Text(match_~ : TextMatch, value~ : String)
  /// The highest, or with `bottom` the lowest, cells or percentage: `top10`.
  Rank(count~ : Int32, bottom~ : Bool, percent~ : Bool)
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
/// The seventeen icon sets the base `ST_IconSetType` admits (ECMA-376
/// §18.18.42), by their OOXML names.
pub let icon_set_styles : Array[String] = [
  "3Arrows", "3ArrowsGray", "3Flags", "3Signs", "3Symbols", "3Symbols2", "3TrafficLights1",
  "3TrafficLights2", "4Arrows", "4ArrowsGray", "4Rating", "4RedToBlack", "4TrafficLights",
  "5Arrows", "5ArrowsGray", "5Quarters", "5Rating",
]

///|
/// Icon sets Excel offers and the backend cannot write: added in Excel 2010,
/// they live only in the `x14` extension schema, and the backend writes only
/// the base `<iconSet>` attribute (ECMA-376 §18.18.42), so it refuses them
/// (moonbitlang/office.mbt#403). Named here so the loader can say why.
pub let unwritable_icon_set_styles : Array[String] = [
  "3Stars", "3Triangles", "5Boxes",
]

///|
/// Excel's cap on a `Rank` rule by count, as its own dialog enforces it.
pub let max_rank_count : Int32 = 1000

///|
/// Excel's cap on a `Rank` rule by percentage.
pub let max_rank_percent : Int32 = 100

///|
/// A conditional format over a range. Its `style` goes to `dxfs` and overrides
/// only what it sets; `stop_if_true` skips later rules on a matched cell.
pub(all) struct ConditionalFormat {
  at : CellRange
  rule : ConditionalRule
  style : Style?
  stop_if_true : Bool
} derive(Eq, Debug)

///|
/// Where a hyperlink goes. A `Location` stays text because Excel accepts a
/// defined name there as readily as `Summary!A1`.
pub(all) enum LinkTarget {
  /// Somewhere outside the workbook — a URL, or a `mailto:`/`file:` target.
  Url(String)
  /// Somewhere inside the workbook: `Summary!A1`, or a defined name.
  Location(String)
} derive(Eq, Debug)

///|
/// A note on a cell (formerly a comment). An author is always written, so
/// `None` leaves the backend's default rather than omitting it.
pub(all) struct Comment {
  at : @units.CellRef
  text : String
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

///|
/// A sheet's auto filter: the range whose top row carries the dropdowns, and
/// the criteria saved on its columns, at most one per column.
pub(all) struct AutoFilter {
  at : CellRange
  columns : Array[FilterColumn]
} derive(Eq, Debug)

///|
/// The criterion saved on one filter column; `column` is the sheet's 1-based
/// column, inside the filter's range.
pub(all) struct FilterColumn {
  column : Int32
  criterion : FilterCriterion
} derive(Eq, Debug)

///|
/// What a filter column keeps: Excel's checkbox list of displayed values, or
/// one comparison ("Custom Filter").
pub(all) enum FilterCriterion {
  Values(Array[String])
  Compare(Comparison)
} derive(Eq, Debug)
