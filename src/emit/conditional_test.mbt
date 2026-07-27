// Round-trip tests for conditional formats: each compiles to real `.xlsx` bytes
// and is read back with the backend's reader.

///|
/// A workbook whose one sheet carries `rule` over `B2:B9`, with `style`.
fn with_rule(
  rule : @model.ConditionalRule,
  style? : @model.Style,
  stop_if_true? : Bool = false,
) -> @model.Workbook {
  let (wb, sheet) = fixture()
  sheet.add_conditional_format({
    at: range("B2", "B9"),
    rule,
    style,
    stop_if_true,
  })
  wb
}

///|
/// The sole conditional format the round-tripped workbook carries.
fn only_format(wb : @model.Workbook) -> @xlsx.ConditionalFormatOptions raise {
  let reopened = reopen(wb)
  let formats = reopened.get_conditional_formats("S")
  guard formats.get("B2:B9") is Some(rules) else {
    fail("expected a conditional format over B2:B9")
  }
  assert_eq(rules.length(), 1)
  rules[0]
}

///|
/// A style that is only a fill, for rules that need one.
fn highlight() -> @model.Style {
  {
    font: None,
    fill: Some({ color: @units.Color::parse("C6EFCE").unwrap() }),
    borders: None,
    align: None,
    number_format: None,
    protection: None,
  }
}

///|
/// The reader reports a criteria in its own human vocabulary rather than the
/// OOXML operator the file holds — `notBetween` comes back as `not between`.
/// The mapping is one-to-one, so these still pin each comparison to a distinct
/// operator; what reaches the file was read out of the XML directly.
test "each comparison round-trips as its conditional criteria" {
  let expected = [
    (@model.Comparison::Between(Number(1.0), Number(10.0)), "between"),
    (NotBetween(Number(1.0), Number(10.0)), "not between"),
    (Equal(Number(5.0)), "equal to"),
    (NotEqual(Number(5.0)), "not equal to"),
    (AtLeast(Number(0.0)), "greater than or equal to"),
    (AtMost(Number(100.0)), "less than or equal to"),
    (GreaterThan(Number(3.0)), "greater than"),
    (LessThan(Number(40.0)), "less than"),
  ]
  for entry in expected {
    let (check, criteria) = entry
    let format = only_format(with_rule(CellIs(check), style=highlight()))
    assert_eq(format.format_type, "cell")
    assert_eq(format.criteria, criteria)
  }
}

///|
test "a two-endpoint comparison round-trips both endpoints" {
  let format = only_format(
    with_rule(CellIs(Between(Number(1.0), Number(10.0))), style=highlight()),
  )
  assert_eq(format.min_value, "1")
  assert_eq(format.max_value, "10")
}

///|
test "a text bound is quoted, and a date becomes its serial" {
  let text = only_format(
    with_rule(CellIs(Equal(Text("Paid"))), style=highlight()),
  )
  assert_eq(text.value, "\"Paid\"")
  let date = only_format(
    with_rule(
      CellIs(AtLeast(Date(@units.DateTime::parse("2026-01-01").unwrap()))),
      style=highlight(),
    ),
  )
  assert_eq(date.value, "46023")
}

///|
test "a formula rule round-trips its expression" {
  let format = only_format(
    with_rule(Formula("AND($B2>0, $C2<0)"), style=highlight()),
  )
  // The backend carries an expression rule's formula in `criteria`, which is
  // the one place it differs from every other rule kind.
  assert_eq(format.criteria, "AND($B2>0, $C2<0)")
}

///|
test "each text match round-trips as its OOXML criteria" {
  let expected = [
    (@model.TextMatch::Contains, "containing"),
    (NotContains, "not containing"),
    (BeginsWith, "begins with"),
    (EndsWith, "ends with"),
  ]
  for entry in expected {
    let (match_, criteria) = entry
    let format = only_format(
      with_rule(Text(match_~, value="urgent"), style=highlight()),
    )
    assert_eq(format.format_type, "text")
    assert_eq(format.criteria, criteria)
    assert_eq(format.value, "urgent")
  }
}

///|
test "a rank round-trips its count, its end, and its percentage" {
  let top = only_format(
    with_rule(Rank(count=10, bottom=false, percent=false), style=highlight()),
  )
  assert_eq(top.format_type, "top")
  assert_eq(top.value, "10")
  assert_false(top.percent)
  let bottom = only_format(
    with_rule(Rank(count=25, bottom=true, percent=true), style=highlight()),
  )
  assert_eq(bottom.format_type, "bottom")
  assert_eq(bottom.value, "25")
  assert_true(bottom.percent)
}

///|
test "duplicate and unique round-trip" {
  assert_eq(
    only_format(with_rule(Duplicate, style=highlight())).format_type,
    "duplicate",
  )
  assert_eq(
    only_format(with_rule(Unique, style=highlight())).format_type,
    "unique",
  )
}

///|
test "a color scale round-trips two or three stops" {
  let color = hex => @units.Color::parse(hex).unwrap()
  let two = only_format(
    with_rule(
      ColorScale(low=color("F8696B"), middle=None, high=color("63BE7B")),
    ),
  )
  assert_eq(two.format_type, "2_color_scale")
  // The reader prefixes a colour with `#`; the file holds `FFF8696B`.
  assert_eq(two.min_color, "#F8696B")
  assert_eq(two.max_color, "#63BE7B")
  let three = only_format(
    with_rule(
      ColorScale(
        low=color("F8696B"),
        middle=Some(color("FFEB84")),
        high=color("63BE7B"),
      ),
    ),
  )
  assert_eq(three.format_type, "3_color_scale")
  assert_eq(three.mid_color, "#FFEB84")
}

///|
test "a data bar round-trips its color" {
  let format = only_format(
    with_rule(
      DataBar(color=@units.Color::parse("638EC6").unwrap(), bar_only=true),
    ),
  )
  assert_eq(format.format_type, "data_bar")
  assert_eq(format.bar_color, "#638EC6")
  assert_true(format.bar_only)
}

///|
test "an icon set round-trips its style and its flags" {
  let format = only_format(
    with_rule(IconSet(style="5Rating", reverse=true, icons_only=true)),
  )
  assert_eq(format.format_type, "icon_set")
  assert_eq(format.icon_style, "5Rating")
  assert_true(format.reverse_icons)
  assert_true(format.icons_only)
}

///|
/// The model repeats the backend's icon-set list so an unknown name fails as a
/// schema diagnostic. This is what keeps the copy honest: every name the loader
/// would accept has to survive emission.
test "every icon set the model lists is one the backend emits" {
  for style in @model.icon_set_styles {
    let format = only_format(
      with_rule(IconSet(style~, reverse=false, icons_only=false)),
    )
    assert_eq(format.icon_style, style)
  }
}

///|
test "stop_if_true round-trips" {
  let format = only_format(
    with_rule(Duplicate, style=highlight(), stop_if_true=true),
  )
  assert_true(format.stop_if_true)
}

///|
test "a style becomes a differential format id" {
  let format = only_format(with_rule(Duplicate, style=highlight()))
  assert_eq(format.format, Some(0))
}

///|
/// ADR-004 at the conditional-format table: a look shared by several rules is
/// registered once, so the file carries one copy however many rules wear it.
test "rules sharing a style share one differential format id" {
  let (wb, sheet) = fixture()
  let shared = highlight()
  let other : @model.Style = { ..shared, number_format: Some("0.0%") }
  for
    entry in [
      (range("A1", "A9"), shared),
      (range("B1", "B9"), shared),
      (range("C1", "C9"), other),
      (range("D1", "D9"), shared),
    ] {
    let (at, style) = entry
    sheet.add_conditional_format({
      at,
      rule: Duplicate,
      style: Some(style),
      stop_if_true: false,
    })
  }
  let reopened = reopen(wb)
  let formats = reopened.get_conditional_formats("S")
  let id = key => {
    guard formats.get(key) is Some(rules) else { fail("no rule at \{key}") }
    rules[0].format
  }
  // Three rules, one id; the odd one out gets its own.
  assert_eq(id("A1:A9"), Some(0))
  assert_eq(id("B1:B9"), Some(0))
  assert_eq(id("D1:D9"), Some(0))
  assert_eq(id("C1:C9"), Some(1))
}

///|
test "conditional formats are emitted in declaration order, which is priority" {
  let (wb, sheet) = fixture()
  sheet.add_conditional_format({
    at: range("A1", "A9"),
    rule: Duplicate,
    style: Some(highlight()),
    stop_if_true: false,
  })
  sheet.add_conditional_format({
    at: range("B1", "B9"),
    rule: Unique,
    style: Some(highlight()),
    stop_if_true: false,
  })
  let reopened = reopen(wb)
  let formats = reopened.get_conditional_formats("S")
  assert_eq(formats.get("A1:A9").unwrap()[0].format_type, "duplicate")
  assert_eq(formats.get("B1:B9").unwrap()[0].format_type, "unique")
}
