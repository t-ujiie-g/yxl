///|
test "an inline list validation keeps its choices in order" {
  let wb = load_ok(
    sheet_spec(
      "    validations:\n      - at: B2:B9\n        list: [Draft, Sent, Paid]\n",
    ),
  )
  let validation = wb.sheets[0].validations[0]
  assert_eq(validation.at.top_left.to_a1(), "B2")
  guard validation.rule is List(choices) else {
    fail("expected an inline list")
  }
  assert_eq(choices, ["Draft", "Sent", "Paid"])
  // Excel's "Ignore blank" is ticked by default, and so is ours.
  assert_true(validation.allow_blank)
}

///|
test "list choices may be numbers, which Excel stores as text" {
  let wb = load_ok(
    sheet_spec(
      "    validations:\n      - at: B2:B9\n        list: [2024, 2025]\n",
    ),
  )
  guard wb.sheets[0].validations[0].rule is List(choices) else {
    fail("expected an inline list")
  }
  assert_eq(choices, ["2024", "2025"])
}

///|
test "a list may be sourced from another sheet" {
  let wb = load_ok(
    "sheets:\n  - name: S\n    validations:\n      - at: B2:B9\n        list: { from: \"Lists!A1:A3\" }\n  - name: Lists\n",
  )
  guard wb.sheets[0].validations[0].rule is ListFrom(source) else {
    fail("expected a sourced list")
  }
  assert_eq(source.sheet, Some("Lists"))
  assert_eq(source.range.top_left.to_a1(), "A1")
  assert_eq(source.range.bottom_right.to_a1(), "A3")
}

///|
test "a quoted sheet name in a list source is unquoted, doubled quotes and all" {
  let wb = load_ok(
    "sheets:\n  - name: S\n    validations:\n      - at: B2:B9\n        list: { from: \"'It''s data'!A1:A3\" }\n  - name: \"It's data\"\n",
  )
  guard wb.sheets[0].validations[0].rule is ListFrom(source) else {
    fail("expected a sourced list")
  }
  assert_eq(source.sheet, Some("It's data"))
}

///|
test "a list source may name this sheet by omitting one" {
  let wb = load_ok(
    sheet_spec(
      "    validations:\n      - at: B2:B9\n        list: { from: E1:E3 }\n",
    ),
  )
  guard wb.sheets[0].validations[0].rule is ListFrom(source) else {
    fail("expected a sourced list")
  }
  assert_eq(source.sheet, None)
}

///|
test "a sourced list takes exactly the one key 'from'" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: B2:B9\n        list: { from: E1:E3, sheet: S }\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'B2:B9' 'list' as a mapping takes exactly one key, 'from'",
    ),
  )
}

///|
test "a list sourced from an undeclared sheet is a diagnostic" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: B2:B9\n        list: { from: \"Lists!A1:A3\" }\n",
      ),
    ),
    Some(
      "spec.yaml: validation on sheet 'S' sources its list from sheet 'Lists', which is not declared",
    ),
  )
}

///|
test "an inline list over Excel's length limit is refused with the length" {
  // 26 choices of 9 characters plus 25 commas is 259, just over 255.
  let choices = Array::makei(26, index => "choice-\{index % 10}\{index % 10}")
  let source = sheet_spec(
    "    validations:\n      - at: B2:B9\n        list: [" +
    choices.join(", ") +
    "]\n",
  )
  assert_eq(
    schema_message(source),
    Some(
      "spec.yaml: validation 'B2:B9' 'list' is 259 characters joined, over Excel's limit of 255 — source it from cells with 'list: { from: … }' instead",
    ),
  )
}

///|
test "an empty list is a diagnostic rather than a dead dropdown" {
  assert_eq(
    schema_message(
      sheet_spec("    validations:\n      - at: B2:B9\n        list: []\n"),
    ),
    Some("spec.yaml: validation 'B2:B9' 'list' is empty"),
  )
}

///|
test "each comparison maps to its own operator" {
  let cases = [
    ("whole", "between: [1, 10]"),
    ("whole", "not_between: [1, 10]"),
    ("decimal", "equals: 0.5"),
    ("decimal", "not_equals: 0.5"),
    ("decimal", "at_least: 0"),
    ("decimal", "at_most: 100"),
    ("text_length", "greater_than: 3"),
    ("text_length", "less_than: 40"),
  ]
  let seen = []
  for entry in cases {
    let (kind, comparison) = entry
    let wb = load_ok(
      sheet_spec(
        "    validations:\n      - at: B2:B9\n        \{kind}: { \{comparison} }\n",
      ),
    )
    guard wb.sheets[0].validations[0].rule is Compare(kind=_, check~) else {
      fail("expected a comparison")
    }
    seen.push(check)
  }
  let one = @model.Bound::Number(1.0)
  let ten = @model.Bound::Number(10.0)
  assert_eq(seen[0], Between(one, ten))
  assert_eq(seen[1], NotBetween(one, ten))
  assert_eq(seen[2], Equal(Number(0.5)))
  assert_eq(seen[3], NotEqual(Number(0.5)))
  assert_eq(seen[4], AtLeast(Number(0.0)))
  assert_eq(seen[5], AtMost(Number(100.0)))
  assert_eq(seen[6], GreaterThan(Number(3.0)))
  assert_eq(seen[7], LessThan(Number(40.0)))
}

///|
test "a date validation reads its bounds as dates" {
  let wb = load_ok(
    sheet_spec(
      "    validations:\n      - at: D2:D9\n        date: { between: [\"2026-01-01\", \"2026-12-31\"] }\n",
    ),
  )
  guard wb.sheets[0].validations[0].rule is Compare(kind~, check~) else {
    fail("expected a comparison")
  }
  assert_true(kind is DateValue)
  guard check is Between(Date(low), Date(high)) else {
    fail("expected two date bounds")
  }
  assert_eq(low.to_serial(Date1900), 46023.0)
  assert_eq(high.to_serial(Date1900), 46387.0)
}

///|
test "a date validation rejects a bound that is not a date" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: D2:D9\n        date: { at_least: 2026 }\n",
      ),
    ),
    Some("spec.yaml: validation 'D2:D9' 'at_least' must be text"),
  )
}

///|
test "a date validation rejects text that is not a date" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: D2:D9\n        date: { at_least: soon }\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'D2:D9' 'at_least' is not a date: 'soon' (expected YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)",
    ),
  )
}

///|
test "the validations key itself must be a sequence" {
  assert_eq(
    schema_message(sheet_spec("    validations: 5\n")),
    Some("spec.yaml: 'validations' must be a sequence"),
  )
}

///|
test "a whole-number validation rejects a fractional bound" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: C2:C9\n        whole: { at_least: 1.5 }\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'C2:C9' 'at_least' must be a whole number: '1.5' (use 'decimal' for fractions)",
    ),
  )
}

///|
test "between takes exactly two bounds" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: C2:C9\n        whole: { between: [1] }\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'C2:C9' 'between' takes exactly two bounds, [low, high]",
    ),
  )
}

///|
test "a rule takes exactly one comparison" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: C2:C9\n        whole: { at_least: 1, at_most: 9 }\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'C2:C9' rule takes exactly one comparison ('between', 'not_between', 'equals', 'not_equals', 'at_least', 'at_most', 'greater_than', or 'less_than')",
    ),
  )
}

///|
test "an unknown comparison is named in the diagnostic" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: C2:C9\n        whole: { above: 1 }\n",
      ),
    ),
    Some(
      "spec.yaml: unknown comparison 'above' in validation 'C2:C9' (expected 'between', 'not_between', 'equals', 'not_equals', 'at_least', 'at_most', 'greater_than', or 'less_than')",
    ),
  )
}

///|
test "a validation needs a rule" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: C2:C9\n        allow_blank: false\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'C2:C9' needs a rule: 'list', 'whole', 'decimal', 'text_length', or 'date'",
    ),
  )
}

///|
test "a validation needs a range" {
  assert_eq(
    schema_message(sheet_spec("    validations:\n      - list: [a]\n")),
    Some("spec.yaml: a validation is missing required key 'at'"),
  )
}

///|
test "a validation rejects an unknown key" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: C2:C9\n        list: [a]\n        colour: red\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'colour' in validation 'C2:C9' (expected 'at', 'list', 'whole', 'decimal', 'text_length', or 'date', 'allow_blank', 'prompt', or 'error')",
    ),
  )
}

///|
test "prompt and error messages load with their style" {
  let wb = load_ok(
    sheet_spec(
      (
        #|    validations:
        #|      - at: B2:B9
        #|        list: [a, b]
        #|        allow_blank: false
        #|        prompt: { title: Pick, body: "a or b" }
        #|        error: { title: Nope, body: "a or b only", style: warning }
        #|
      ),
    ),
  )
  let validation = wb.sheets[0].validations[0]
  assert_false(validation.allow_blank)
  assert_eq(validation.prompt.unwrap().title, "Pick")
  assert_eq(validation.prompt.unwrap().body, "a or b")
  let error = validation.error.unwrap()
  assert_eq(error.title, "Nope")
  assert_true(error.style is Warning)
}

///|
test "an error message defaults to the stop style" {
  let wb = load_ok(
    sheet_spec(
      "    validations:\n      - at: B2:B9\n        list: [a]\n        error: { body: no }\n",
    ),
  )
  assert_true(wb.sheets[0].validations[0].error.unwrap().style is Stop)
}

///|
test "an unknown error style is named in the diagnostic" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: B2:B9\n        list: [a]\n        error: { body: no, style: shout }\n",
      ),
    ),
    Some(
      "spec.yaml: unknown validation 'B2:B9' 'error' style 'shout' (expected 'stop', 'warning', or 'information')",
    ),
  )
}

///|
test "an empty message is a diagnostic rather than a blank popup" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: B2:B9\n        list: [a]\n        prompt: {}\n",
      ),
    ),
    Some("spec.yaml: validation 'B2:B9' 'prompt' needs a 'title' or a 'body'"),
  )
}

///|
test "a message rejects an unknown key" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: B2:B9\n        list: [a]\n        prompt: { text: hi }\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'text' in validation 'B2:B9' 'prompt' (expected 'title' or 'body')",
    ),
  )
}
