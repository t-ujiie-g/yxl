///|
/// Attach the sheet's auto filter with its saved criteria.
fn apply_filter(
  backend : @xlsx.Workbook,
  sheet_name : String,
  filter : @model.AutoFilter,
  date_system : @units.DateSystem,
) -> Unit raise {
  let range = filter.at.to_a1()
  let lists : Array[@xlsx.AutoFilterValuesOption] = []
  let comparisons : Array[@xlsx.AutoFilterOption] = []
  for entry in filter.columns {
    let column = @units.column_letters(entry.column)
    match entry.criterion {
      Values(values) => lists.push({ column, values, })
      Compare(comparison) =>
        comparisons.push({
          column,
          expression: filter_expression(comparison, date_system),
        })
    }
  }
  backend.set_auto_filter(sheet_name, range, comparisons)
  guard !lists.is_empty() else { return }
  // Each backend entry point replaces the whole filter, so the comparison
  // columns are carried over into the one the value lists build.
  guard backend.sheet(sheet_name) is Some(worksheet) &&
    worksheet.auto_filter is Some(compared) else {
    return
  }
  let carried = compared.columns.copy()
  backend.set_auto_filter_values(sheet_name, range, lists)
  if worksheet.auto_filter is Some(merged) {
    merged.columns.append(carried)
    merged.columns.sort_by_key(column => column.col)
  }
}

///|
/// A comparison in the backend's filter grammar: `x >= 10`, joined by `and` or
/// `or` for the two-sided ones.
fn filter_expression(
  comparison : @model.Comparison,
  date_system : @units.DateSystem,
) -> String raise @diag.EmitError {
  let term = (operator : String, bound : @model.Bound) => {
    "x \{operator} \{filter_operand(bound, date_system)}"
  }
  match comparison {
    Equal(bound) => term("==", bound)
    NotEqual(bound) => term("!=", bound)
    AtLeast(bound) => term(">=", bound)
    AtMost(bound) => term("<=", bound)
    GreaterThan(bound) => term(">", bound)
    LessThan(bound) => term("<", bound)
    Between(low, high) => term(">=", low) + " and " + term("<=", high)
    NotBetween(low, high) => term("<", low) + " or " + term(">", high)
  }
}

///|
/// One filter operand. The grammar reads a bare or quoted `blanks`/`nonblanks`
/// as the empty-cell filter, so text spelling either is refused.
fn filter_operand(
  bound : @model.Bound,
  date_system : @units.DateSystem,
) -> String raise @diag.EmitError {
  let number = match bound {
    Number(number) => number
    Date(datetime) => datetime.to_serial(date_system)
    Text(text) => {
      if text.to_lower() is ("blanks" | "nonblanks") {
        raise @diag.EmitError(
          @diag.Diagnostic(
            "a filter comparison against the text '\{text}' cannot be written: the Excel backend reads it as its empty-cell filter",
          ),
        )
      }
      return quote_literal(text)
    }
  }
  match exact_int(number) {
    Some(whole) => whole.to_string()
    None => number.to_string()
  }
}

///|
/// Attach one data validation: what it accepts over which cells, whether blanks
/// pass, and the two optional messages.
fn apply_validation(
  backend : @xlsx.Workbook,
  sheet_name : String,
  validation : @model.Validation,
  date_system : @units.DateSystem,
) -> Unit raise {
  let dv = @xlsx.DataValidation::new(validation.allow_blank)
  dv.set_sqref(validation.at.to_a1())
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
) -> Unit raise {
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
/// Attach a note to a cell. The backend takes rich-text paragraphs as well as
/// plain text; the spec offers only the latter, so the paragraph list is empty
/// and Excel draws the note in its default font.
fn apply_comment(
  backend : @xlsx.Workbook,
  sheet_name : String,
  comment : @model.Comment,
) -> Unit raise {
  backend.add_comment(sheet_name, {
    cell: comment.at.to_a1(),
    author: comment.author.unwrap_or(""),
    author_id: None,
    text: comment.text,
    paragraph: [],
    width: None,
    height: None,
  })
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
/// One endpoint as a formula literal: a date as its serial, a whole number
/// without `.0`, text quoted.
fn bound_formula(
  bound : @model.Bound,
  date_system : @units.DateSystem,
) -> @xlsx.DataValidationFormula {
  let number = match bound {
    Number(number) => number
    Date(datetime) => datetime.to_serial(date_system)
    Text(text) => return TextValue(quote_literal(text))
  }
  match exact_int(number) {
    Some(whole) => IntValue(whole)
    None => DoubleValue(number)
  }
}

///|
/// The `Int` a double stands for exactly, or `None` when it has a fraction or
/// sits outside `Int`'s range.
fn exact_int(number : Double) -> Int32? {
  if number == number.trunc() &&
    number >= @int.MIN_VALUE.to_double() &&
    number <= @int.MAX_VALUE.to_double() {
    Some(number.to_int())
  } else {
    None
  }
}

///|
/// Text as an Excel formula string literal: wrapped in quotes, with any inner
/// quote doubled.
fn quote_literal(text : String) -> String {
  "\"" + text.replace_all(old="\"", new="\"\"") + "\""
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
