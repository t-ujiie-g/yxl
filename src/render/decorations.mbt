///|
/// The decorations a sheet carries, appended in the order `docs/spec.md` §10
/// presents them.
fn decorations(
  sheet : @model.Sheet,
  entries : Array[(String, @yaml.Node)],
) -> Unit {
  if sheet.filter is Some(range) {
    entries.push(("filter", @yaml.Str(range.to_a1())))
  }
  if !sheet.validations.is_empty() {
    let rendered = []
    for validation in sheet.validations {
      rendered.push(one_validation(validation))
    }
    entries.push(("validations", @yaml.Seq(rendered)))
  }
  if !sheet.links.is_empty() {
    let rendered = []
    for link in sheet.links {
      rendered.push((link.at.to_a1(), one_link(link)))
    }
    entries.push(("links", @yaml.Map(rendered)))
  }
  if !sheet.comments.is_empty() {
    let rendered = []
    for comment in sheet.comments {
      rendered.push((comment.at.to_a1(), one_comment(comment)))
    }
    entries.push(("comments", @yaml.Map(rendered)))
  }
  if !sheet.conditional_formats.is_empty() {
    let rendered = []
    for format in sheet.conditional_formats {
      rendered.push(one_conditional(format))
    }
    entries.push(("conditional", @yaml.Seq(rendered)))
  }
  if !sheet.tables.is_empty() {
    let rendered = []
    for table in sheet.tables {
      rendered.push(one_table(table))
    }
    entries.push(("tables", @yaml.Seq(rendered)))
  }
}

///|
/// A link: the bare URL where there is nothing else to say, and the mapping
/// where there is.
fn one_link(link : @model.Link) -> @yaml.Node {
  let (key, target) = match link.target {
    Url(url) => ("url", url)
    Location(location) => ("to", location)
  }
  match (key, link.tip) {
    ("url", None) => @yaml.Str(target)
    (_, None) => @yaml.Map([(key, @yaml.Str(target))])
    (_, Some(tip)) =>
      @yaml.Map([(key, @yaml.Str(target)), ("tip", @yaml.Str(tip))])
  }
}

///|
/// A note: the bare text where the author is Excel's own, the mapping where the
/// file names one.
fn one_comment(comment : @model.Comment) -> @yaml.Node {
  match comment.author {
    None => @yaml.Str(comment.text)
    Some(author) =>
      @yaml.Map([
        ("text", @yaml.Str(comment.text)),
        ("author", @yaml.Str(author)),
      ])
  }
}

///|
/// A table, with only the toggles that differ from Excel's own defaults —
/// banded rows on, everything else off.
fn one_table(table : @model.Table) -> @yaml.Node {
  let entries = [("at", @yaml.Str(table.at.to_a1()))]
  if table.name is Some(name) {
    entries.push(("name", @yaml.Str(name)))
  }
  if table.style is Some(style) {
    entries.push(("style", @yaml.Str(style)))
  }
  if !table.banded_rows {
    entries.push(("banded_rows", @yaml.Bool(false)))
  }
  if table.banded_columns {
    entries.push(("banded_columns", @yaml.Bool(true)))
  }
  if table.first_column {
    entries.push(("first_column", @yaml.Bool(true)))
  }
  if table.last_column {
    entries.push(("last_column", @yaml.Bool(true)))
  }
  @yaml.Map(entries)
}

///|
/// A validation: the range, the rule, and the messages around it.
fn one_validation(validation : @model.Validation) -> @yaml.Node {
  let entries = [("at", @yaml.Str(validation.at.to_a1()))]
  match validation.rule {
    List(choices) => {
      let rendered = []
      for choice in choices {
        rendered.push(@yaml.Str(choice))
      }
      entries.push(("list", @yaml.Seq(rendered)))
    }
    ListFrom(source) =>
      entries.push(
        ("list", @yaml.Map([("from", @yaml.Str(sheet_range(source)))])),
      )
    Compare(kind~, check~) =>
      entries.push((validation_kind(kind), comparison(check)))
  }
  // Excel's own dialog leaves "Ignore blank" ticked, so only the other way is
  // worth writing down.
  if !validation.allow_blank {
    entries.push(("allow_blank", @yaml.Bool(false)))
  }
  if validation.prompt is Some(prompt) {
    entries.push(
      (
        "prompt",
        @yaml.Map([
          ("title", @yaml.Str(prompt.title)),
          ("body", @yaml.Str(prompt.body)),
        ]),
      ),
    )
  }
  if validation.error is Some(error) {
    let inner = [
      ("title", @yaml.Str(error.title)),
      ("body", @yaml.Str(error.body)),
    ]
    // `stop` is Excel's default, and the schema's.
    match error.style {
      Stop => ()
      Warning => inner.push(("style", @yaml.Str("warning")))
      Information => inner.push(("style", @yaml.Str("information")))
    }
    entries.push(("error", @yaml.Map(inner)))
  }
  @yaml.Map(entries)
}

///|
fn validation_kind(kind : @model.ValidationKind) -> String {
  match kind {
    Whole => "whole"
    Decimal => "decimal"
    TextLength => "text_length"
    DateValue => "date"
  }
}

///|
/// A comparison as its one-key mapping: `{ between: [a, b] }`, `{ ">": x }`.
fn comparison(check : @model.Comparison) -> @yaml.Node {
  match check {
    Between(low, high) =>
      @yaml.Map([("between", @yaml.Seq([bound(low), bound(high)]))])
    NotBetween(low, high) =>
      @yaml.Map([("not_between", @yaml.Seq([bound(low), bound(high)]))])
    Equal(value) => @yaml.Map([("equals", bound(value))])
    NotEqual(value) => @yaml.Map([("not_equals", bound(value))])
    AtLeast(value) => @yaml.Map([("at_least", bound(value))])
    AtMost(value) => @yaml.Map([("at_most", bound(value))])
    GreaterThan(value) => @yaml.Map([("greater_than", bound(value))])
    LessThan(value) => @yaml.Map([("less_than", bound(value))])
  }
}

///|
fn bound(value : @model.Bound) -> @yaml.Node {
  match value {
    Number(number) => number_scalar(number)
    Date(datetime) => @yaml.Str(date_text(datetime))
    Text(text) => @yaml.Str(text)
  }
}

///|
/// A range, qualified by sheet where it names one.
fn sheet_range(range : @model.SheetRange) -> String {
  match range.sheet {
    Some(name) => "\{name}!\{range.range.to_a1()}"
    None => range.range.to_a1()
  }
}

///|
/// One conditional format: the range, the rule, and how a match is drawn.
///
/// A rule that draws its own appearance — a scale, a bar, an icon set — takes no
/// style, and one that highlights needs one, which is the schema's own rule
/// (`docs/spec.md` §10). The look goes out *inline* rather than through `defs.styles`: Excel
/// keeps these in a table of their own, so a conditional look and a cell look
/// that happen to match are not the same entry and naming them together would
/// say they were.
fn one_conditional(format : @model.ConditionalFormat) -> @yaml.Node {
  let entries = [("at", @yaml.Str(format.at.to_a1()))]
  match format.rule {
    CellIs(check) => entries.push(("cell", comparison(check)))
    Formula(expression) => entries.push(("formula", @yaml.Str(expression)))
    Text(match_~, value~) =>
      entries.push(
        (
          "text",
          @yaml.Map([
            (
              match match_ {
                Contains => "contains"
                NotContains => "not_contains"
                BeginsWith => "begins_with"
                EndsWith => "ends_with"
              },
              @yaml.Str(value),
            ),
          ]),
        ),
      )
    Rank(count~, bottom~, percent~) => {
      let inner = [("count", @yaml.Int(count.to_int64()))]
      if percent {
        inner.push(("percent", @yaml.Bool(true)))
      }
      entries.push((if bottom { "bottom" } else { "top" }, @yaml.Map(inner)))
    }
    Duplicate => entries.push(("duplicate", @yaml.Bool(true)))
    Unique => entries.push(("unique", @yaml.Bool(true)))
    ColorScale(low~, middle~, high~) => {
      let inner = [("low", @yaml.Str(low.hex()))]
      if middle is Some(middle) {
        inner.push(("middle", @yaml.Str(middle.hex())))
      }
      inner.push(("high", @yaml.Str(high.hex())))
      entries.push(("color_scale", @yaml.Map(inner)))
    }
    DataBar(color~, bar_only~) => {
      let inner = [("color", @yaml.Str(color.hex()))]
      if bar_only {
        inner.push(("bar_only", @yaml.Bool(true)))
      }
      entries.push(("data_bar", @yaml.Map(inner)))
    }
    IconSet(style~, reverse~, icons_only~) => {
      let inner = [("style", @yaml.Str(style))]
      if reverse {
        inner.push(("reverse", @yaml.Bool(true)))
      }
      if icons_only {
        inner.push(("icons_only", @yaml.Bool(true)))
      }
      entries.push(("icon_set", @yaml.Map(inner)))
    }
  }
  if format.style is Some(style) {
    let format_code = style.number_format
    let rest = { ..style, number_format: None, }
    if !rest.is_empty() {
      entries.push(("style", style_node(rest)))
    }
    if format_code is Some(code) {
      entries.push(("format", @yaml.Str(code)))
    }
  }
  if format.stop_if_true {
    entries.push(("stop_if_true", @yaml.Bool(true)))
  }
  @yaml.Map(entries)
}
