///|
/// A sheet's conditional formats, in the order Excel evaluates them.
fn read_conditional_formats(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  dates : @units.DateSystem,
  notes : Notes,
) -> Unit raise {
  for reference, formats in backend.get_conditional_formats(sheet.name) {
    guard @model.CellRange::parse_loose(reference) is Some(at) else { continue }
    for options in formats {
      guard read_conditional_rule(options, dates, notes) is Some(rule) else {
        continue
      }
      let style = read_conditional_style(backend, options.format, notes)
      // The loader takes a style on a highlighting rule and refuses one on a
      // scale, a bar, or an icon set. A file can violate either half — a dxf
      // holding only what the schema cannot say recovers as no style at all —
      // and writing the violation out would make a spec that will not load.
      if draws_itself(rule) {
        if style is Some(_) {
          notes.drop(
            "a style on a conditional rule that draws its own appearance, which the spec gives no place",
          )
        }
        sheet.add_conditional_format({
          at,
          rule,
          style: None,
          stop_if_true: options.stop_if_true,
        })
        continue
      }
      guard style is Some(_) else {
        notes.drop(
          "a conditional rule whose style holds nothing the spec can say, which would match cells and change nothing",
        )
        continue
      }
      sheet.add_conditional_format({
        at,
        rule,
        style,
        stop_if_true: options.stop_if_true,
      })
    }
  }
}

///|
/// Whether a rule supplies its own appearance rather than applying a style —
/// the same split the loader enforces on a spec's way in.
fn draws_itself(rule : @model.ConditionalRule) -> Bool {
  rule is (ColorScale(..) | DataBar(..) | IconSet(..))
}

///|
/// The look a matching cell is drawn in. Excel keeps these in a table of their
/// own (`dxfs`), so the id has to be resolved through the matching accessor
/// rather than the one cells use.
fn read_conditional_style(
  backend : @xlsx.Workbook,
  id : Int?,
  notes : Notes,
) -> @model.Style? raise {
  guard id is Some(id) else { return None }
  let style = read_style(backend, backend.get_conditional_style(id), notes)
  if style.is_empty() {
    None
  } else {
    Some(style)
  }
}

///|
/// One rule, or `None` where the schema has no way to say it.
fn read_conditional_rule(
  options : @xlsx.ConditionalFormatOptions,
  dates : @units.DateSystem,
  notes : Notes,
) -> @model.ConditionalRule? {
  match options.format_type {
    "cell" =>
      match read_conditional_comparison(options, dates) {
        Some(check) => Some(CellIs(check))
        None => {
          notes.drop(
            "a conditional format comparing with '\{options.criteria}', which the spec has no name for",
          )
          None
        }
      }
    // An expression rule carries its formula in `criteria`, not `value` — the
    // one rule kind that does.
    "formula" =>
      if options.criteria.is_empty() {
        None
      } else {
        Some(Formula(options.criteria))
      }
    "text" =>
      match text_match(options.criteria) {
        Some(match_) => Some(Text(match_~, value=options.value))
        None => {
          notes.drop(
            "a conditional format matching text by '\{options.criteria}', which the spec has no name for",
          )
          None
        }
      }
    "top" | "bottom" => {
      let count = @string.parse_int(options.value) catch { _ => return None }
      Some(
        Rank(
          count~,
          bottom=options.format_type == "bottom",
          percent=options.percent,
        ),
      )
    }
    "duplicate" => Some(Duplicate)
    "unique" => Some(Unique)
    "2_color_scale" | "3_color_scale" => {
      guard read_color(Some(options.min_color), notes) is Some(low) &&
        read_color(Some(options.max_color), notes) is Some(high) else {
        return None
      }
      // The schema's scale is its colours; the *stops* Excel places them at are
      // its own defaults, which is what an author gets either way.
      if options.min_type != "min" || options.max_type != "max" {
        notes.drop(
          "a colour scale placed at chosen stops rather than at the range's own low and high",
        )
      }
      Some(
        ColorScale(
          low~,
          middle=if options.format_type == "3_color_scale" {
            read_color(Some(options.mid_color), notes)
          } else {
            None
          },
          high~,
        ),
      )
    }
    "data_bar" =>
      match read_color(Some(options.bar_color), notes) {
        Some(color) => Some(DataBar(color~, bar_only=options.bar_only))
        None => None
      }
    "icon_set" => {
      guard !options.icon_style.is_empty() else { return None }
      guard @model.icon_set_styles.contains(options.icon_style) else {
        // The three Excel 2010 added are named apart: the spec knows them, and
        // what it cannot do is write one back (`model/decorations.mbt`). Saying
        // "does not name" of those would send the reader looking for a typo.
        notes.drop(
          if @model.unwritable_icon_set_styles.contains(options.icon_style) {
            "the '\{options.icon_style}' icon set, which the Excel backend cannot write back without making the workbook one Excel offers to repair"
          } else {
            "the '\{options.icon_style}' icon set, which the spec does not name"
          },
        )
        return None
      }
      Some(
        IconSet(
          style=options.icon_style,
          reverse=options.reverse_icons,
          icons_only=options.icons_only,
        ),
      )
    }
    other => {
      notes.drop(
        "a '\{other}' conditional format, which the spec has no rule for",
      )
      None
    }
  }
}

///|
/// The eight comparisons, read from the backend's display spelling. `between`
/// and its negation take their endpoints from the min/max pair; the rest read
/// the single `value`, which is how the emitter writes them.
fn read_conditional_comparison(
  options : @xlsx.ConditionalFormatOptions,
  dates : @units.DateSystem,
) -> @model.Comparison? {
  match options.criteria {
    "between" | "not between" => {
      guard conditional_bound(options.min_value, dates) is Some(low) &&
        conditional_bound(options.max_value, dates) is Some(high) else {
        return None
      }
      if options.criteria == "between" {
        Some(Between(low, high))
      } else {
        Some(NotBetween(low, high))
      }
    }
    criteria => {
      guard conditional_bound(options.value, dates) is Some(value) else {
        return None
      }
      match criteria {
        "equal to" => Some(Equal(value))
        "not equal to" => Some(NotEqual(value))
        "greater than or equal to" => Some(AtLeast(value))
        "less than or equal to" => Some(AtMost(value))
        "greater than" => Some(GreaterThan(value))
        "less than" => Some(LessThan(value))
        _ => None
      }
    }
  }
}

///|
/// One endpoint, read as what it looks like.
///
/// A conditional format's bound is a formula literal: a number, or text in
/// double quotes as the emitter wrote it. Unlike a validation's, its kind is not
/// fixed by the rule, so the text has to say which it is. A bare number stays a
/// number — turning one into a date would be the guess `read_scalar` refuses for
/// the same reason.
fn conditional_bound(
  literal : String,
  dates : @units.DateSystem,
) -> @model.Bound? {
  ignore(dates)
  guard !literal.is_empty() else { return None }
  if literal.has_prefix("\"") &&
    literal.has_suffix("\"") &&
    literal.length() >= 2 {
    // Excel doubles an inner quote, as the emitter's `quote_literal` does.
    return Some(
      Text(
        literal[1:literal.length() - 1]
        .to_owned()
        .replace_all(old="\"\"", new="\""),
      ),
    )
  }
  Some(Number(@string.parse_double(literal))) catch {
    _ => Some(Text(literal))
  }
}

///|
fn text_match(criteria : String) -> @model.TextMatch? {
  match criteria {
    "containing" => Some(Contains)
    "not containing" => Some(NotContains)
    "begins with" => Some(BeginsWith)
    "ends with" => Some(EndsWith)
    _ => None
  }
}
