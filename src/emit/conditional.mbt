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
      // These four take the three colour bytes and prepend the alpha
      // themselves, so an `AARRGGBB` handed over here reaches the file as ten
      // hex digits.
      options.set_min_color(low.rgb())
      options.set_max_color(high.rgb())
      if middle is Some(middle) {
        options.set_mid_color(middle.rgb())
      }
      options
    }
    DataBar(color~, bar_only~) => {
      let options = @xlsx.ConditionalFormatOptions::new("data_bar")
      options.set_bar_color(color.rgb())
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
