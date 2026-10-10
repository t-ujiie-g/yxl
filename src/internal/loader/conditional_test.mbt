///|
/// A one-sheet spec whose sheet carries one conditional format built from
/// `body`, with `good` declared as a style it can reference.
fn conditional_spec(body : String) -> String {
  "defs:\n  styles:\n    good: { fill: \"C6EFCE\" }\n" +
  sheet_spec("    conditional:\n      - at: B2:B9\n        " + body + "\n")
}

///|
/// The sole conditional format the spec loads.
fn only_format(source : String) -> @model.ConditionalFormat raise {
  let formats = load_ok(source).sheets[0].conditional_formats
  assert_eq(formats.length(), 1)
  formats[0]
}

///|
test "a cell rule reads the same comparisons a validation does" {
  let format = only_format(
    conditional_spec("cell: { at_least: 1000000 }\n        style: good"),
  )
  assert_eq(format.at.top_left.to_a1(), "B2")
  assert_true(format.rule is CellIs(AtLeast(Number(1000000.0))))
  assert_false(format.stop_if_true)
}

///|
test "a cell rule infers a number, a date, or text from what is written" {
  let cases = [
    ("at_least: 10", @model.Bound::Number(10.0)),
    ("equals: Paid", Text("Paid")),
    (
      "at_least: \"2026-01-01\"",
      Date(@units.DateTime::parse("2026-01-01").unwrap()),
    ),
  ]
  for entry in cases {
    let (comparison, expected) = entry
    let format = only_format(
      conditional_spec("cell: { \{comparison} }\n        style: good"),
    )
    guard format.rule is CellIs(check) else { fail("expected a cell rule") }
    let bound = match check {
      AtLeast(bound) | Equal(bound) => bound
      _ => fail("expected a one-endpoint comparison")
    }
    assert_eq(bound, expected)
  }
}

///|
test "an inline style is accepted where a declared one would be" {
  let format = only_format(
    conditional_spec(
      "cell: { at_least: 1 }\n        style: { fill: \"FFC7CE\" }",
    ),
  )
  assert_eq(format.style.unwrap().fill.unwrap().color.hex(), "FFC7CE")
}

///|
test "a number format alone is style enough" {
  let format = only_format(
    conditional_spec("cell: { at_least: 1 }\n        format: \"0.0%\""),
  )
  assert_eq(format.style.unwrap().number_format, Some("0.0%"))
}

///|
test "stop_if_true loads" {
  let format = only_format(
    conditional_spec(
      "cell: { at_least: 1 }\n        style: good\n        stop_if_true: true",
    ),
  )
  assert_true(format.stop_if_true)
}

///|
test "a formula rule keeps its expression verbatim" {
  let format = only_format(
    conditional_spec("formula: \"AND($B2>0, $C2<0)\"\n        style: good"),
  )
  assert_true(format.rule is Formula("AND($B2>0, $C2<0)"))
}

///|
test "each text match loads" {
  let cases = [
    ("contains", @model.TextMatch::Contains),
    ("not_contains", NotContains),
    ("begins_with", BeginsWith),
    ("ends_with", EndsWith),
  ]
  for entry in cases {
    let (key, expected) = entry
    let format = only_format(
      conditional_spec("text: { \{key}: urgent }\n        style: good"),
    )
    guard format.rule is Text(match_~, value~) else {
      fail("expected a text rule")
    }
    assert_eq(match_, expected)
    assert_eq(value, "urgent")
  }
}

///|
test "a text rule takes exactly one match" {
  assert_eq(
    schema_message(
      conditional_spec(
        "text: { contains: a, ends_with: b }\n        style: good",
      ),
    ),
    Some(
      "spec.yaml: conditional 'B2:B9' 'text' takes exactly one of 'contains', 'not_contains', 'begins_with', or 'ends_with'",
    ),
  )
}

///|
test "top and bottom take a bare count" {
  for entry in [("top", false), ("bottom", true)] {
    let (key, expected_bottom) = entry
    let format = only_format(
      conditional_spec("\{key}: 10\n        style: good"),
    )
    guard format.rule is Rank(count~, bottom~, percent~) else {
      fail("expected a rank rule")
    }
    assert_eq(count, 10)
    assert_eq(bottom, expected_bottom)
    assert_false(percent)
  }
}

///|
test "a rank may be a percentage" {
  let format = only_format(
    conditional_spec(
      "bottom: { count: 25, percent: true }\n        style: good",
    ),
  )
  assert_true(format.rule is Rank(count=25, bottom=true, percent=true))
}

///|
test "a rank is held to the limit Excel's own dialog enforces" {
  assert_eq(
    schema_message(conditional_spec("top: 1001\n        style: good")),
    Some(
      "spec.yaml: conditional 'B2:B9' 'top' must be between 1 and 1000, not 1001",
    ),
  )
  // As a percentage the cap is 100, not 1000.
  assert_eq(
    schema_message(
      conditional_spec(
        "top: { count: 101, percent: true }\n        style: good",
      ),
    ),
    Some(
      "spec.yaml: conditional 'B2:B9' 'top' must be between 1 and 100, not 101",
    ),
  )
}

///|
test "a rank written as a mapping needs its count" {
  assert_eq(
    schema_message(
      conditional_spec("top: { percent: true }\n        style: good"),
    ),
    Some("spec.yaml: conditional 'B2:B9' 'top' is missing required key 'count'"),
  )
}

///|
test "a rank beyond Int cannot wrap into range" {
  assert_eq(
    schema_message(conditional_spec("top: 4294967297\n        style: good")),
    Some(
      "spec.yaml: conditional 'B2:B9' 'top' must be between 1 and 1000, not 4294967297",
    ),
  )
}

///|
test "duplicate and unique load from their marker" {
  let duplicate = only_format(
    conditional_spec("duplicate: true\n        style: good"),
  )
  assert_true(duplicate.rule is Duplicate)
  let unique = only_format(
    conditional_spec("unique: true\n        style: good"),
  )
  assert_true(unique.rule is Unique)
}

///|
test "a false marker is refused rather than silently ignored" {
  assert_eq(
    schema_message(conditional_spec("duplicate: false\n        style: good")),
    Some(
      "spec.yaml: conditional 'B2:B9' 'duplicate' must be true — leave the key out rather than setting it false",
    ),
  )
}

///|
test "a color scale takes two or three stops" {
  let two = only_format(
    conditional_spec("color_scale: { low: \"F8696B\", high: \"63BE7B\" }"),
  )
  guard two.rule is ColorScale(low~, middle~, high~) else {
    fail("expected a color scale")
  }
  assert_eq(low.hex(), "F8696B")
  assert_eq(high.hex(), "63BE7B")
  assert_eq(middle, None)
  let three = only_format(
    conditional_spec(
      "color_scale: { low: \"F8696B\", middle: \"FFEB84\", high: \"63BE7B\" }",
    ),
  )
  guard three.rule is ColorScale(middle=Some(middle), ..) else {
    fail("expected a three-stop scale")
  }
  assert_eq(middle.hex(), "FFEB84")
}

///|
test "a color scale needs both ends" {
  assert_eq(
    schema_message(conditional_spec("color_scale: { low: \"F8696B\" }")),
    Some(
      "spec.yaml: conditional 'B2:B9' 'color_scale' needs both 'low' and 'high'",
    ),
  )
}

///|
test "a data bar takes a color and an optional bar-only flag" {
  let format = only_format(
    conditional_spec("data_bar: { color: \"638EC6\", bar_only: true }"),
  )
  guard format.rule is DataBar(color~, bar_only~) else {
    fail("expected a data bar")
  }
  assert_eq(color.hex(), "638EC6")
  assert_true(bar_only)
}

///|
test "a data bar needs its color" {
  assert_eq(
    schema_message(conditional_spec("data_bar: { bar_only: true }")),
    Some(
      "spec.yaml: conditional 'B2:B9' 'data_bar' is missing required key 'color'",
    ),
  )
}

///|
test "an icon set takes a bare name or a mapping" {
  let bare = only_format(conditional_spec("icon_set: 3TrafficLights1"))
  assert_true(
    bare.rule
    is IconSet(style="3TrafficLights1", reverse=false, icons_only=false),
  )
  let full = only_format(
    conditional_spec(
      "icon_set: { style: 5Rating, reverse: true, icons_only: true }",
    ),
  )
  assert_true(
    full.rule is IconSet(style="5Rating", reverse=true, icons_only=true),
  )
}

///|
test "an icon set written as a mapping needs its style" {
  assert_eq(
    schema_message(conditional_spec("icon_set: { reverse: true }")),
    Some(
      "spec.yaml: conditional 'B2:B9' 'icon_set' is missing required key 'style'",
    ),
  )
}

///|
test "an unknown icon set is refused, and the diagnostic lists the real ones" {
  guard schema_message(conditional_spec("icon_set: 3Emoji")) is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_true(message.has_prefix("spec.yaml: unknown icon set '3Emoji'"))
  assert_true(message.contains("3TrafficLights1"))
  assert_true(message.contains("5Rating"))
}

///|
/// The three Excel 2010 added exist only in the `x14` schema, and the backend
/// writes the name into the base attribute — so a workbook naming one is
/// schema-invalid and Excel offers to repair it. Refused by name, with the
/// reason, rather than left to be discovered on open.
test "an icon set the backend cannot write is refused by name, with the reason" {
  for style in @model.unwritable_icon_set_styles {
    guard schema_message(conditional_spec("icon_set: \{style}"))
      is Some(message) else {
      fail("expected a diagnostic for '\{style}'")
    }
    assert_true(message.contains("asks for '\{style}'"))
    assert_true(message.contains("§18.18.42"))
    assert_true(message.contains("would not open cleanly"))
  }
}

///|
/// The refused three and the accepted seventeen are disjoint and together are
/// the twenty `docs/spec.md` §10 describes. A name drifting from one list to
/// the other, or into both, is the mistake this pins.
test "the icon sets the spec names are the seventeen legal ones plus three refused" {
  assert_eq(@model.icon_set_styles.length(), 17)
  assert_eq(@model.unwritable_icon_set_styles.length(), 3)
  for style in @model.unwritable_icon_set_styles {
    assert_false(@model.icon_set_styles.contains(style))
  }
}

///|
test "a highlighting rule without a style would change nothing, so it is refused" {
  assert_eq(
    schema_message(conditional_spec("cell: { at_least: 1 }")),
    Some(
      "spec.yaml: conditional 'B2:B9' needs a 'style' (or a 'format') to apply where it matches",
    ),
  )
}

///|
test "a rule that draws itself refuses a style it could not apply" {
  assert_eq(
    schema_message(
      conditional_spec("data_bar: { color: \"638EC6\" }\n        style: good"),
    ),
    Some(
      "spec.yaml: conditional 'B2:B9' draws its own appearance, so it takes no 'style' or 'format'",
    ),
  )
}

///|
test "a conditional format needs a range and a rule" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    conditional:\n      - style: good\n",
    ),
    Some("spec.yaml: a conditional format is missing required key 'at'"),
  )
  assert_eq(
    schema_message(conditional_spec("stop_if_true: true")),
    Some(
      "spec.yaml: conditional 'B2:B9' needs a rule: 'cell', 'formula', 'text', 'top', 'bottom', 'duplicate', 'unique', 'color_scale', 'data_bar', or 'icon_set'",
    ),
  )
}

///|
test "a conditional format rejects an unknown key" {
  assert_eq(
    schema_message(
      conditional_spec(
        "cell: { at_least: 1 }\n        style: good\n        colour: red",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'colour' in conditional 'B2:B9' (expected 'at', 'cell', 'formula', 'text', 'top', 'bottom', 'duplicate', 'unique', 'color_scale', 'data_bar', or 'icon_set', 'style', 'format', or 'stop_if_true')",
    ),
  )
}

///|
test "a conditional format references a declared style, or says so" {
  assert_eq(
    schema_message(
      conditional_spec("cell: { at_least: 1 }\n        style: missing"),
    ),
    Some("spec.yaml: conditional 'B2:B9' references undefined style 'missing'"),
  )
}

///|
test "conditional formats keep declaration order, which is priority order" {
  let wb = load_ok(
    "defs:\n  styles:\n    good: { fill: \"C6EFCE\" }\n" +
    sheet_spec(
      "    conditional:\n      - at: A1:A9\n        top: 1\n        style: good\n      - at: B1:B9\n        unique: true\n        style: good\n",
    ),
  )
  let formats = wb.sheets[0].conditional_formats
  assert_eq(formats.length(), 2)
  assert_eq(formats[0].at.top_left.to_a1(), "A1")
  assert_true(formats[1].rule is Unique)
}

///|
test "a conditional bound must be a scalar" {
  assert_eq(
    schema_message(
      conditional_spec("cell: { at_least: [1, 2] }\n        style: good"),
    ),
    Some(
      "spec.yaml: conditional 'B2:B9' 'at_least' must be text, a number, or a boolean",
    ),
  )
}
