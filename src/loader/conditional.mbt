// Loading `conditional:` — formatting decided by a cell's value rather than its
// address. Split from `decorations.mbt`, which holds the other sheet keys that
// decorate rather than fill; the comparison vocabulary is shared from there, so
// `at_least` means the same thing in both.

///|
/// One endpoint of a conditional format's comparison, read as what it looks
/// like: a number, a date if the text parses as one, and otherwise the text
/// itself — Excel compares a cell against any of the three.
fn infer_bound(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> @model.Bound raise @diag.SchemaError {
  match node {
    @yaml.Int(number) => Number(number.to_double())
    @yaml.Float(number) => Number(number)
    @yaml.Str(text) =>
      match @units.DateTime::parse(text) {
        Some(datetime) => Date(datetime)
        None => Text(text)
      }
    _ => raise not_scalar(file~, context=what)
  }
}

///|
/// The rule keys a conditional format may carry, one of which is required.
const CONDITIONAL_RULES : String = "'cell', 'formula', 'text', 'top', 'bottom', 'duplicate', 'unique', 'color_scale', 'data_bar', or 'icon_set'"

///|
/// A sheet's `conditional:` — a sequence of formats, each over a range.
/// Declaration order is Excel's priority order.
fn load_conditional_formats(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'conditional'") {
    sheet.add_conditional_format(load_conditional_format(item, file~, defs~))
  }
}

///|
/// One `conditional:` entry: the range, exactly one rule, and how a matching
/// cell is drawn.
fn load_conditional_format(
  node : @yaml.Node,
  file~ : String,
  defs~ : Defs,
) -> @model.ConditionalFormat raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a conditional format")
  let at = anchor_range(
    entries,
    file~,
    subject="a conditional format",
    noun="conditional",
  )
  let context = "conditional '\{at.to_a1()}'"
  let mut rule : @model.ConditionalRule? = None
  let mut style_node = None
  let mut number_format = None
  let mut stop_if_true = false
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "cell" =>
        rule = Some(
          CellIs(
            load_comparison(
              value,
              file~,
              read_bound=(node, what) => infer_bound(node, file~, what~),
              context~,
            ),
          ),
        )
      "formula" =>
        rule = Some(
          Formula(expect_string(value, file~, context="\{context} 'formula'")),
        )
      "text" => rule = Some(load_text_rule(value, file~, context~))
      "top" | "bottom" =>
        rule = Some(
          load_rank_rule(value, file~, bottom=key == "bottom", context~),
        )
      "duplicate" | "unique" => {
        expect_marker(value, file~, what="\{context} '\{key}'")
        rule = Some(if key == "duplicate" { Duplicate } else { Unique })
      }
      "color_scale" => rule = Some(load_color_scale(value, file~, context~))
      "data_bar" => rule = Some(load_data_bar(value, file~, context~))
      "icon_set" => rule = Some(load_icon_set(value, file~, context~))
      "style" => style_node = Some(value)
      "format" =>
        number_format = Some(
          expect_string(value, file~, context="\{context} 'format'"),
        )
      "stop_if_true" =>
        stop_if_true = expect_bool(
          value,
          file~,
          context="\{context} 'stop_if_true'",
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', \{CONDITIONAL_RULES}, 'style', 'format', or 'stop_if_true')",
        )
    }
  }
  guard rule is Some(rule) else {
    raise schema_error(file~, "\{context} needs a rule: \{CONDITIONAL_RULES}")
  }
  let style = combine_style(style_node, number_format, file~, defs~, context~)
  // A scale, a bar, and an icon set draw their own appearance, so a style would
  // have nothing to apply; a highlighting rule without one would match cells and
  // then change nothing. Both are mistakes worth reporting.
  if draws_itself(rule) {
    guard style is None else {
      raise schema_error(
        file~,
        "\{context} draws its own appearance, so it takes no 'style' or 'format'",
      )
    }
  } else {
    guard style is Some(_) else {
      raise schema_error(
        file~,
        "\{context} needs a 'style' (or a 'format') to apply where it matches",
      )
    }
  }
  { at, rule, style, stop_if_true }
}

///|
/// Whether a rule supplies its own appearance rather than applying a style.
fn draws_itself(rule : @model.ConditionalRule) -> Bool {
  rule is (ColorScale(..) | DataBar(..) | IconSet(..))
}

///|
/// A rule key whose only sensible value is `true`: `duplicate: false` reads like
/// "format the non-duplicates", which is not what it would do, so it is refused
/// rather than quietly ignored.
fn expect_marker(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> Unit raise @diag.SchemaError {
  guard expect_bool(node, file~, context=what) else {
    raise schema_error(
      file~,
      "\{what} must be true — leave the key out rather than setting it false",
    )
  }
}

///|
/// A `text:` rule — which part of the cell's text to look at, and for what.
fn load_text_rule(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ConditionalRule raise @diag.SchemaError {
  let what = "\{context} 'text'"
  let entries = expect_map(node, file~, context=what)
  guard entries.length() == 1 else {
    raise schema_error(
      file~,
      "\{what} takes exactly one of 'contains', 'not_contains', 'begins_with', or 'ends_with'",
    )
  }
  let (key, value) = entries[0]
  let match_ : @model.TextMatch = match key {
    "contains" => Contains
    "not_contains" => NotContains
    "begins_with" => BeginsWith
    "ends_with" => EndsWith
    _ =>
      raise schema_error(
        file~,
        "unknown key '\{key}' in \{what} (expected 'contains', 'not_contains', 'begins_with', or 'ends_with')",
      )
  }
  Text(match_~, value=expect_string(value, file~, context="\{what} '\{key}'"))
}

///|
/// A `top:` / `bottom:` rule — a bare count, or `{ count, percent }`.
fn load_rank_rule(
  node : @yaml.Node,
  file~ : String,
  bottom~ : Bool,
  context~ : String,
) -> @model.ConditionalRule raise @diag.SchemaError {
  let key = if bottom { "bottom" } else { "top" }
  let what = "\{context} '\{key}'"
  let mut count = None
  let mut percent = false
  if node is @yaml.Map(entries) {
    for entry in entries {
      let (inner, value) = entry
      match inner {
        "count" =>
          count = Some(expect_count(value, file~, what="\{what} count"))
        "percent" =>
          percent = expect_bool(value, file~, context="\{what} 'percent'")
        _ =>
          raise schema_error(
            file~,
            "unknown key '\{inner}' in \{what} (expected 'count' or 'percent')",
          )
      }
    }
    guard count is Some(_) else {
      raise schema_error(file~, "\{what} is missing required key 'count'")
    }
  } else {
    count = Some(expect_count(node, file~, what~))
  }
  let count = count.unwrap()
  // Checked before narrowing, so an absurd number cannot wrap into range.
  let limit = if percent {
    @model.max_rank_percent.to_int64()
  } else {
    @model.max_rank_count.to_int64()
  }
  guard count >= 1L && count <= limit else {
    raise schema_error(
      file~,
      "\{what} must be between 1 and \{limit}, not \{count}",
    )
  }
  Rank(count=count.to_int(), bottom~, percent~)
}

///|
/// A whole number, as written — narrowed only once the caller has checked it
/// against the limit that applies.
fn expect_count(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> Int64 raise @diag.SchemaError {
  guard node is @yaml.Int(count) else {
    raise schema_error(file~, "\{what} must be a whole number")
  }
  count
}

///|
/// A `color_scale:` rule — two or three colors, low to high. The values Excel
/// anchors them at are its defaults: the range's minimum, its 50th percentile,
/// and its maximum.
fn load_color_scale(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ConditionalRule raise @diag.SchemaError {
  let what = "\{context} 'color_scale'"
  let mut low = None
  let mut middle = None
  let mut high = None
  for entry in expect_map(node, file~, context=what) {
    let (key, value) = entry
    match key {
      "low" =>
        low = Some(expect_color(value, file~, what="'low'", context=what))
      "middle" =>
        middle = Some(expect_color(value, file~, what="'middle'", context=what))
      "high" =>
        high = Some(expect_color(value, file~, what="'high'", context=what))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{what} (expected 'low', 'middle', or 'high')",
        )
    }
  }
  guard low is Some(low) && high is Some(high) else {
    raise schema_error(file~, "\{what} needs both 'low' and 'high'")
  }
  ColorScale(low~, middle~, high~)
}

///|
/// A `data_bar:` rule — the bar's color, and whether the value is hidden behind
/// it.
fn load_data_bar(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ConditionalRule raise @diag.SchemaError {
  let what = "\{context} 'data_bar'"
  let mut color = None
  let mut bar_only = false
  for entry in expect_map(node, file~, context=what) {
    let (key, value) = entry
    match key {
      "color" =>
        color = Some(expect_color(value, file~, what="'color'", context=what))
      "bar_only" =>
        bar_only = expect_bool(value, file~, context="\{what} 'bar_only'")
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{what} (expected 'color' or 'bar_only')",
        )
    }
  }
  guard color is Some(color) else {
    raise schema_error(file~, "\{what} is missing required key 'color'")
  }
  DataBar(color~, bar_only~)
}

///|
/// An `icon_set:` rule — a bare style name, or `{ style, reverse, icons_only }`.
fn load_icon_set(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ConditionalRule raise @diag.SchemaError {
  let what = "\{context} 'icon_set'"
  let mut style = None
  let mut reverse = false
  let mut icons_only = false
  if node is @yaml.Map(entries) {
    for entry in entries {
      let (key, value) = entry
      match key {
        "style" =>
          style = Some(expect_string(value, file~, context="\{what} 'style'"))
        "reverse" =>
          reverse = expect_bool(value, file~, context="\{what} 'reverse'")
        "icons_only" =>
          icons_only = expect_bool(value, file~, context="\{what} 'icons_only'")
        _ =>
          raise schema_error(
            file~,
            "unknown key '\{key}' in \{what} (expected 'style', 'reverse', or 'icons_only')",
          )
      }
    }
    guard style is Some(_) else {
      raise schema_error(file~, "\{what} is missing required key 'style'")
    }
  } else {
    style = Some(expect_string(node, file~, context=what))
  }
  let style = style.unwrap()
  // The three the backend would write into a base attribute that has no room
  // for them are refused by name, so the author gets the reason instead of
  // "unknown" (ADR-006) — and, more to the point, instead of a workbook Excel
  // offers to repair.
  if @model.unwritable_icon_set_styles.contains(style) {
    raise schema_error(
      file~,
      "\{what} asks for '\{style}', which Excel 2010 added and the Excel backend writes into the base 'iconSet' attribute, whose ECMA-376 §18.18.42 enumeration does not have it — the workbook would not open cleanly. Pick one of the seventeen the base schema names, or wait for the upstream fix",
    )
  }
  guard @model.icon_set_styles.contains(style) else {
    raise unknown_value(
      style,
      file~,
      what="icon set",
      context=what,
      expected=@model.icon_set_styles.map(name => "'\{name}'"),
    )
  }
  IconSet(style~, reverse~, icons_only~)
}
