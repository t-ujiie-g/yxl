///|
/// A one-sheet spec whose sheet carries `body`, indented to sit under it.
/// Shared with the `validations:`, `conditional:`, and `properties:` tests.
fn sheet_spec(body : String) -> String {
  "sheets:\n  - name: S\n" + body
}

///|
test "filter loads as a canonical range" {
  let wb = load_ok(sheet_spec("    filter: A1:C50\n"))
  let filter = wb.sheets[0].filter.unwrap().at
  assert_eq(filter.top_left.to_a1(), "A1")
  assert_eq(filter.bottom_right.to_a1(), "C50")
}

///|
fn filter_spec(columns : String) -> String {
  sheet_spec("    filter:\n      at: A1:D20\n      columns:\n" + columns)
}

///|
test "filter columns load as value lists and comparisons" {
  let wb = load_ok(
    filter_spec(
      (
        #|        - { at: A, values: [North America, EMEA, APAC, 2024] }
        #|        - { at: C, between: [100, 200] }
        #|        - { at: D, equals: "Paid" }
      ),
    ),
  )
  let filter = wb.sheets[0].filter.unwrap()
  assert_eq(filter.at.to_a1(), "A1:D20")
  assert_eq(filter.columns, [
    { column: 1, criterion: Values(["North America", "EMEA", "APAC", "2024"]), },
    { column: 3, criterion: Compare(Between(Number(100.0), Number(200.0))), },
    { column: 4, criterion: Compare(Equal(Text("Paid"))), },
  ])
}

///|
test "a filter written as a mapping without columns is the plain range" {
  let wb = load_ok(sheet_spec("    filter: { at: A1:D20 }\n"))
  assert_eq(wb.sheets[0].filter.unwrap().columns, [])
}

///|
test "a filter column that cannot be written is refused with the reason" {
  let cases = [
    ("        - { values: [a] }\n", "needs 'at'"),
    (
      "        - { at: F, values: [a] }\n", "outside the filter's range 'A1:D20'",
    ),
    ("        - { at: a1, values: [a] }\n", "must be a column letter"),
    (
      "        - { at: A, values: [a] }\n        - { at: A, at_least: 1 }\n", "'A' is given twice",
    ),
    ("        - { at: A, values: [a], at_least: 1 }\n", "exactly one criterion"),
    ("        - { at: A }\n", "exactly one criterion"),
    ("        - { at: A, values: [] }\n", "'values' is empty"),
    ("        - { at: A, values: [1.5] }\n", "text or whole numbers"),
    ("        - { at: A, top: 10 }\n", "asks for a 'top' filter"),
    ("        - { at: A, color: red }\n", "asks for a 'color' filter"),
    ("        - { at: A, around: 3 }\n", "unknown comparison 'around'"),
  ]
  for case in cases {
    let (columns, expected) = case
    guard schema_message(filter_spec(columns)) is Some(message) else {
      fail("expected a diagnostic for \{columns}")
    }
    assert_true(message.contains(expected), msg="\{message}")
  }
  guard schema_message(sheet_spec("    filter: { columns: [] }\n"))
    is Some(message) else {
    fail("expected a diagnostic for a filter with no range")
  }
  assert_true(message.contains("filter needs 'at'"))
  guard schema_message(sheet_spec("    filter: { at: A1:B2, sort: true }\n"))
    is Some(message) else {
    fail("expected a diagnostic for an unknown filter key")
  }
  assert_true(message.contains("unknown key 'sort' in filter"))
}

///|
test "filter corners may be written in either order" {
  let wb = load_ok(sheet_spec("    filter: C50:A1\n"))
  let filter = wb.sheets[0].filter.unwrap().at
  assert_eq(filter.top_left.to_a1(), "A1")
  assert_eq(filter.bottom_right.to_a1(), "C50")
}

///|
test "filter rejects a value that is not a range" {
  assert_eq(
    schema_message(sheet_spec("    filter: A1\n")),
    Some("spec.yaml: filter range 'A1' must be 'TopLeft:BottomRight'"),
  )
}

///|
test "a bare link value is an external URL" {
  let wb = load_ok(sheet_spec("    links:\n      A1: https://example.com\n"))
  let link = wb.sheets[0].links[0]
  assert_eq(link.at.to_a1(), "A1")
  assert_true(link.target is Url("https://example.com"))
  assert_eq(link.tip, None)
}

///|
test "an expanded link carries a target and a tooltip" {
  let wb = load_ok(
    sheet_spec(
      (
        #|    links:
        #|      B2: { url: "https://example.com/q3", tip: "The Q3 report" }
        #|
      ),
    ),
  )
  let link = wb.sheets[0].links[0]
  assert_true(link.target is Url("https://example.com/q3"))
  assert_eq(link.tip, Some("The Q3 report"))
}

///|
test "a link may point inside the workbook" {
  let wb = load_ok(
    "sheets:\n  - name: S\n    links:\n      A1: { to: \"Other!A1\" }\n  - name: Other\n",
  )
  assert_true(wb.sheets[0].links[0].target is Location("'Other'!A1"))
}

///|
/// A sheet name Excel would not accept bare is the case this quoting exists
/// for: unquoted, `Q1 Sales!B2` is not a reference and the link is dead.
test "a link into a sheet whose name needs quoting gets it" {
  let wb = load_ok(
    "sheets:\n  - name: S\n    links:\n      A1: { to: \"Q1 Sales!B2\" }\n  - name: Q1 Sales\n",
  )
  assert_true(wb.sheets[0].links[0].target is Location("'Q1 Sales'!B2"))
}

///|
/// An apostrophe in the name doubles inside the quotes, as Excel spells it.
test "a link quotes an apostrophe in the sheet name by doubling it" {
  let wb = load_ok(
    "sheets:\n  - name: S\n    links:\n      A1: { to: \"O'Brien!A1\" }\n  - name: O'Brien\n",
  )
  assert_true(wb.sheets[0].links[0].target is Location("'O''Brien'!A1"))
}

///|
/// Already-quoted stays quoted rather than picking up a second layer, and the
/// sheet-existence check still sees through it.
test "a link that was already quoted is left as one" {
  let wb = load_ok(
    "sheets:\n  - name: S\n    links:\n      A1: { to: \"'Q1 Sales'!B2\" }\n  - name: Q1 Sales\n",
  )
  assert_true(wb.sheets[0].links[0].target is Location("'Q1 Sales'!B2"))
}

///|
/// A target naming no sheet is a defined name, and quoting one would turn it
/// into a reference to a sheet nothing declares.
test "a link to a defined name is left exactly as written" {
  let wb = load_ok(
    "sheets:\n  - name: S\n    links:\n      A1: { to: Totals }\n",
  )
  assert_true(wb.sheets[0].links[0].target is Location("Totals"))
}

///|
test "a link needs exactly one kind of target" {
  assert_eq(
    schema_message(sheet_spec("    links:\n      A1: { tip: hello }\n")),
    Some(
      "spec.yaml: link 'A1' needs 'url' (outside the workbook) or 'to' (inside it)",
    ),
  )
}

///|
test "a link rejects an unknown key" {
  assert_eq(
    schema_message(sheet_spec("    links:\n      A1: { href: x }\n")),
    Some(
      "spec.yaml: unknown key 'href' in link 'A1' (expected 'url', 'to', or 'tip')",
    ),
  )
}

///|
test "a link key must be a cell reference" {
  assert_eq(
    schema_message(sheet_spec("    links:\n      A0: https://x\n")),
    Some("spec.yaml: 'A0' is not a valid A1 cell reference in 'links'"),
  )
}

///|
test "a link into an undeclared sheet is a diagnostic" {
  assert_eq(
    schema_message(sheet_spec("    links:\n      A1: { to: \"Gone!A1\" }\n")),
    Some(
      "spec.yaml: link at 'A1' on sheet 'S' points at sheet 'Gone', which is not declared",
    ),
  )
}

///|
test "an unqualified link location is left alone, being a defined name" {
  let wb = load_ok(sheet_spec("    links:\n      A1: { to: tax_rate }\n"))
  assert_true(wb.sheets[0].links[0].target is Location("tax_rate"))
}

///|
test "a bare comment is its text" {
  let wb = load_ok(sheet_spec("    comments:\n      B2: Restated in Q3.\n"))
  let comment = wb.sheets[0].comments[0]
  assert_eq(comment.at.to_a1(), "B2")
  assert_eq(comment.text, "Restated in Q3.")
  assert_eq(comment.author, None)
}

///|
test "a comment may name its author" {
  let wb = load_ok(
    sheet_spec(
      "    comments:\n      A2: { text: Includes ANZ., author: Finance }\n",
    ),
  )
  let comment = wb.sheets[0].comments[0]
  assert_eq(comment.text, "Includes ANZ.")
  assert_eq(comment.author, Some("Finance"))
}

///|
test "a comment needs its text" {
  assert_eq(
    schema_message(sheet_spec("    comments:\n      A2: { author: Finance }\n")),
    Some("spec.yaml: comment 'A2' is missing required key 'text'"),
  )
}

///|
test "a comment rejects an unknown key" {
  assert_eq(
    schema_message(sheet_spec("    comments:\n      A2: { note: hi }\n")),
    Some(
      "spec.yaml: unknown key 'note' in comment 'A2' (expected 'text' or 'author')",
    ),
  )
}

///|
test "a comment key must be a cell reference" {
  assert_eq(
    schema_message(sheet_spec("    comments:\n      A0: hi\n")),
    Some("spec.yaml: 'A0' is not a valid A1 cell reference in 'comments'"),
  )
}

///|
test "comments keep declaration order" {
  let wb = load_ok(
    sheet_spec("    comments:\n      C3: third\n      A1: first\n"),
  )
  let comments = wb.sheets[0].comments
  assert_eq(comments[0].at.to_a1(), "C3")
  assert_eq(comments[1].at.to_a1(), "A1")
}

///|
test "an unterminated quoted sheet name is a diagnostic, not a silent miss" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: B2:B9\n        list: { from: \"'Lists!A1:A3\" }\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'B2:B9' 'list' from ''Lists!A1:A3' has an unterminated quoted sheet name (expected \"'Sheet name'!A1:B9\")",
    ),
  )
}

///|
test "a list source that is not a range is a diagnostic" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    validations:\n      - at: B2:B9\n        list: { from: \"Lists!A1\" }\n",
      ),
    ),
    Some(
      "spec.yaml: validation 'B2:B9' 'list' from 'A1' must be 'TopLeft:BottomRight'",
    ),
  )
}
