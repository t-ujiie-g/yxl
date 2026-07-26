// Emitting the decorations laid over a sheet's cells: the auto filter, data
// validations, and hyperlinks. Like the rest of `emit`, this is the only side
// of the seam that names `@xlsx` (ADR-002).

///|
/// Put Excel's filter dropdowns over a range. No per-column criteria are passed:
/// the spec has no way to express them yet, and an empty list is how the backend
/// spells "just the dropdowns".
fn apply_filter(
  backend : @xlsx.Workbook,
  sheet_name : String,
  range : @model.CellRange,
) -> Unit raise @xlsx.XlsxError {
  backend.set_auto_filter(sheet_name, plain_range(range), [])
}

///|
/// Attach one data validation: what it accepts over which cells, whether blanks
/// pass, and the two optional messages.
fn apply_validation(
  backend : @xlsx.Workbook,
  sheet_name : String,
  validation : @model.Validation,
  date_system : @units.DateSystem,
) -> Unit raise @xlsx.XlsxError {
  let dv = @xlsx.DataValidation::new(validation.allow_blank)
  dv.set_sqref(plain_range(validation.at))
  match validation.rule {
    List(choices) => dv.set_drop_list(choices[:])
    ListFrom(source) =>
      // Despite the name, this sets the *source* of a drop-down; the cells it
      // applies to were set by `set_sqref` above.
      dv.set_sqref_drop_list(
        absolute_range(source.sheet.unwrap_or(sheet_name), source.range),
      )
    Compare(kind~, check~) => {
      let (first, second, operator) = comparison_parts(check, date_system)
      dv.set_range(first, second, validation_type(kind), operator)
    }
  }
  if validation.prompt is Some(prompt) {
    dv.set_input(prompt.title, prompt.body)
  }
  if validation.error is Some(error) {
    dv.set_error(error_style(error.style), error.title, error.body)
  }
  backend.add_data_validation(sheet_name, dv)
}

///|
/// Link a cell. No display text is passed: Excel shows the cell's own value, so
/// setting one would record a string nobody sees (the model documents this).
fn apply_link(
  backend : @xlsx.Workbook,
  sheet_name : String,
  link : @model.Link,
) -> Unit raise @xlsx.XlsxError {
  let (target, link_type) = match link.target {
    Url(url) => (url, @xlsx.HyperlinkType::External)
    Location(location) => (location, @xlsx.HyperlinkType::Location)
  }
  backend.set_cell_hyperlink(
    sheet_name,
    link.at.to_a1(),
    target,
    link_type,
    tooltip?=link.tip,
  )
}

///|
/// A range as the plain `A1:B9` reference Excel uses for an `sqref` or an auto
/// filter — relative, and never sheet-qualified, since both are stored inside
/// the sheet they apply to.
fn plain_range(range : @model.CellRange) -> String {
  range.top_left.to_a1() + ":" + range.bottom_right.to_a1()
}

///|
/// A comparison as the backend's two formula slots and its operator. The
/// one-endpoint operators leave the second slot empty, which is what Excel
/// expects — `formula2` belongs only to `between` / `notBetween`.
fn comparison_parts(
  check : @model.Comparison,
  date_system : @units.DateSystem,
) -> (
  @xlsx.DataValidationFormula,
  @xlsx.DataValidationFormula,
  @xlsx.DataValidationOperator,
) {
  let empty = @xlsx.DataValidationFormula::TextValue("")
  let bound = bound => bound_formula(bound, date_system)
  match check {
    Between(low, high) => (bound(low), bound(high), Between)
    NotBetween(low, high) => (bound(low), bound(high), NotBetween)
    Equal(value) => (bound(value), empty, Equal)
    NotEqual(value) => (bound(value), empty, NotEqual)
    AtLeast(value) => (bound(value), empty, GreaterThanOrEqual)
    AtMost(value) => (bound(value), empty, LessThanOrEqual)
    GreaterThan(value) => (bound(value), empty, GreaterThan)
    LessThan(value) => (bound(value), empty, LessThan)
  }
}

///|
/// One endpoint as a backend formula value. A date becomes the serial its epoch
/// gives it, and a whole number is written as an integer so the stored formula
/// reads `10` rather than `10.0`.
fn bound_formula(
  bound : @model.Bound,
  date_system : @units.DateSystem,
) -> @xlsx.DataValidationFormula {
  let number = match bound {
    Number(number) => number
    Date(datetime) => datetime.to_serial(date_system)
  }
  if number == number.trunc() &&
    number >= @int.MIN_VALUE.to_double() &&
    number <= @int.MAX_VALUE.to_double() {
    IntValue(number.to_int())
  } else {
    DoubleValue(number)
  }
}

///|
/// The backend's validation type for a model kind.
fn validation_type(kind : @model.ValidationKind) -> @xlsx.DataValidationType {
  match kind {
    Whole => Whole
    Decimal => Decimal
    TextLength => TextLength
    DateValue => Date
  }
}

///|
/// The backend's error style for a model one.
fn error_style(
  style : @model.ValidationErrorStyle,
) -> @xlsx.DataValidationErrorStyle {
  match style {
    Stop => Stop
    Warning => Warning
    Information => Information
  }
}
