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
) -> Unit raise {
  backend.set_auto_filter(sheet_name, range.to_a1(), [])
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
/// Attach one conditional format. Its style, if it has one, is interned into
/// Excel's *differential* format table (`dxfs`) — a table of its own, separate
/// from the `cellXfs` ids cells wear, but interned the same way so a look shared
/// by several rules is registered once (ADR-004).
fn apply_conditional_format(
  backend : @xlsx.Workbook,
  sheet_name : String,
  format : @model.ConditionalFormat,
  dxf_ids : Map[@model.Style, Int],
  date_system : @units.DateSystem,
) -> Unit raise {
  let options = conditional_options(format.rule, date_system)
  options.set_stop_if_true(format.stop_if_true)
  if format.style is Some(style) {
    options.set_format(Some(intern_conditional_style(backend, dxf_ids, style)))
  }
  backend.set_conditional_format(sheet_name, format.at.to_a1(), [options])
}

///|
/// A model rule as the backend's options bundle. The `format_type` strings are
/// the backend's own shorthand, which it maps onto the OOXML `cfRule` types.
fn conditional_options(
  rule : @model.ConditionalRule,
  date_system : @units.DateSystem,
) -> @xlsx.ConditionalFormatOptions {
  match rule {
    CellIs(check) => {
      let options = @xlsx.ConditionalFormatOptions::new("cell")
      let (criteria, first, second) = conditional_criteria(check, date_system)
      options.set_criteria(criteria)
      // `between` and `notBetween` read their two endpoints from the min/max
      // pair; every other operator reads the single `value`.
      match second {
        Some(second) => {
          options.set_min_value(first)
          options.set_max_value(second)
        }
        None => options.set_value(first)
      }
      options
    }
    Formula(expression) => {
      let options = @xlsx.ConditionalFormatOptions::new("formula")
      // An expression rule carries its formula in `criteria`, not `value` —
      // the one rule kind that does.
      options.set_criteria(expression)
      options
    }
    Text(match_~, value~) => {
      let options = @xlsx.ConditionalFormatOptions::new("text")
      options.set_criteria(
        match match_ {
          Contains => "containsText"
          NotContains => "notContains"
          BeginsWith => "beginsWith"
          EndsWith => "endsWith"
        },
      )
      options.set_value(value)
      options
    }
    Rank(count~, bottom~, percent~) => {
      let options = @xlsx.ConditionalFormatOptions::new(
        if bottom {
          "bottom"
        } else {
          "top"
        },
      )
      options.set_value(count.to_string())
      options.set_percent(percent)
      options
    }
    Duplicate => @xlsx.ConditionalFormatOptions::new("duplicate")
    Unique => @xlsx.ConditionalFormatOptions::new("unique")
    ColorScale(low~, middle~, high~) => {
      let options = @xlsx.ConditionalFormatOptions::new(
        match middle {
          Some(_) => "3_color_scale"
          None => "2_color_scale"
        },
      )
      options.set_min_color(low.hex())
      options.set_max_color(high.hex())
      if middle is Some(middle) {
        options.set_mid_color(middle.hex())
      }
      options
    }
    DataBar(color~, bar_only~) => {
      let options = @xlsx.ConditionalFormatOptions::new("data_bar")
      options.set_bar_color(color.hex())
      options.set_bar_only(bar_only)
      options
    }
    IconSet(style~, reverse~, icons_only~) => {
      let options = @xlsx.ConditionalFormatOptions::new("icon_set")
      options.set_icon_style(style)
      options.set_reverse_icons(reverse)
      options.set_icons_only(icons_only)
      options
    }
  }
}

///|
/// A comparison as the backend's criteria name and its one or two endpoints.
/// The OOXML names are passed rather than the symbols the backend also accepts,
/// so what crosses the seam says what it means.
fn conditional_criteria(
  check : @model.Comparison,
  date_system : @units.DateSystem,
) -> (String, String, String?) {
  let literal = bound => bound_literal(bound, date_system)
  match check {
    Between(low, high) => ("between", literal(low), Some(literal(high)))
    NotBetween(low, high) => ("notBetween", literal(low), Some(literal(high)))
    Equal(value) => ("equal", literal(value), None)
    NotEqual(value) => ("notEqual", literal(value), None)
    AtLeast(value) => ("greaterThanOrEqual", literal(value), None)
    AtMost(value) => ("lessThanOrEqual", literal(value), None)
    GreaterThan(value) => ("greaterThan", literal(value), None)
    LessThan(value) => ("lessThan", literal(value), None)
  }
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
/// One endpoint as a backend formula value. A date becomes the serial its epoch
/// gives it, and a whole number is written as an integer so the stored formula
/// reads `10` rather than `10.0`.
///
/// A `Text` bound cannot arrive from a validation — a validation's kind fixes
/// what its bounds may be — but the type admits one, so it is rendered as the
/// quoted literal Excel would need rather than left to a partial match.
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
/// One endpoint as the literal text a formula holds — what a conditional
/// format's `<formula>` element carries, where the backend takes a string
/// rather than a typed value.
fn bound_literal(
  bound : @model.Bound,
  date_system : @units.DateSystem,
) -> String {
  let number = match bound {
    Number(number) => number
    Date(datetime) => datetime.to_serial(date_system)
    Text(text) => return quote_literal(text)
  }
  match exact_int(number) {
    Some(whole) => whole.to_string()
    None => number.to_string()
  }
}

///|
/// The `Int` a double stands for exactly, or `None` when it has a fraction or
/// sits outside `Int`'s range.
fn exact_int(number : Double) -> Int? {
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
