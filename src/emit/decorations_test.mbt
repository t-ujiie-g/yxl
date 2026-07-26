// Round-trip tests for the decorations: each compiles to real `.xlsx` bytes and
// is read back with the backend's reader, so what is asserted is what Excel
// would find in the file.

///|
/// A one-sheet workbook, plus the sheet, ready to decorate.
fn fixture() -> (@model.Workbook, @model.Sheet) {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  (wb, sheet)
}

///|
/// The range `TopLeft:BottomRight`, both corners given in A1.
fn range(top_left : String, bottom_right : String) -> @model.CellRange {
  {
    top_left: @units.CellRef::parse_a1(top_left).unwrap(),
    bottom_right: @units.CellRef::parse_a1(bottom_right).unwrap(),
  }
}

///|
/// The sole validation the round-tripped workbook carries.
fn only_validation(wb : @model.Workbook) -> @xlsx.DataValidation raise {
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  let validations = reopened.get_data_validations("S")
  assert_eq(validations.length(), 1)
  validations[0]
}

///|
test "an auto filter round-trips as a range over the sheet" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef::new(col=1, row=1), Text("Region"))
  sheet.set_filter(range("A1", "C50"))
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  guard reopened.get_auto_filter("S") is Some(filter) else {
    fail("expected an auto filter")
  }
  assert_eq(filter.range_ref, "A1:C50")
}

///|
test "an inline drop-down round-trips as a comma-joined list" {
  let (wb, sheet) = fixture()
  sheet.add_validation({
    at: range("B2", "B9"),
    rule: List(["Draft", "Sent", "Paid"]),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  let validation = only_validation(wb)
  assert_eq(validation.sqref, "B2:B9")
  assert_eq(validation.validation_type, "list")
  assert_eq(validation.formula1, "\"Draft,Sent,Paid\"")
  assert_true(validation.allow_blank)
}

///|
test "a sourced drop-down round-trips as an absolute, sheet-qualified reference" {
  let (wb, sheet) = fixture()
  wb.add_sheet("Lists") |> ignore
  sheet.add_validation({
    at: range("B2", "B9"),
    rule: ListFrom({ sheet: Some("Lists"), range: range("A1", "A3") }),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  let validation = only_validation(wb)
  assert_eq(validation.validation_type, "list")
  // Absolute, so inserting rows above the source cannot shift the list.
  assert_eq(validation.formula1, "'Lists'!$A$1:$A$3")
}

///|
test "a list sourced from no named sheet resolves to the sheet holding it" {
  let (wb, sheet) = fixture()
  sheet.add_validation({
    at: range("B2", "B9"),
    rule: ListFrom({ sheet: None, range: range("E1", "E3") }),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  assert_eq(only_validation(wb).formula1, "'S'!$E$1:$E$3")
}

///|
test "each comparison round-trips as its OOXML operator" {
  let expected = [
    (
      @model.Comparison::Between(Number(1.0), Number(10.0)),
      "between",
      "1",
      "10",
    ),
    (NotBetween(Number(1.0), Number(10.0)), "notBetween", "1", "10"),
    (Equal(Number(5.0)), "equal", "5", ""),
    (NotEqual(Number(5.0)), "notEqual", "5", ""),
    (AtLeast(Number(0.0)), "greaterThanOrEqual", "0", ""),
    (AtMost(Number(100.0)), "lessThanOrEqual", "100", ""),
    (GreaterThan(Number(3.0)), "greaterThan", "3", ""),
    (LessThan(Number(40.0)), "lessThan", "40", ""),
  ]
  for entry in expected {
    let (check, operator, formula1, formula2) = entry
    let (wb, sheet) = fixture()
    sheet.add_validation({
      at: range("C2", "C9"),
      rule: Compare(kind=Whole, check~),
      allow_blank: true,
      prompt: None,
      error: None,
    })
    let validation = only_validation(wb)
    assert_eq(validation.operator, operator)
    assert_eq(validation.formula1, formula1)
    assert_eq(validation.formula2, formula2)
    assert_eq(validation.validation_type, "whole")
  }
}

///|
test "each validation kind round-trips as its OOXML type" {
  let kinds = [
    (@model.ValidationKind::Whole, "whole"),
    (Decimal, "decimal"),
    (TextLength, "textLength"),
  ]
  for entry in kinds {
    let (kind, expected) = entry
    let (wb, sheet) = fixture()
    sheet.add_validation({
      at: range("C2", "C9"),
      rule: Compare(kind~, check=AtLeast(Number(1.0))),
      allow_blank: true,
      prompt: None,
      error: None,
    })
    assert_eq(only_validation(wb).validation_type, expected)
  }
}

///|
test "a date bound round-trips as the serial its epoch gives it" {
  for entry in [(@units.DateSystem::Date1900, "46023"), (Date1904, "44561")] {
    let (date_system, serial) = entry
    let wb = @model.Workbook::new(date_system~)
    let sheet = wb.add_sheet("S")
    sheet.add_validation({
      at: range("D2", "D9"),
      rule: Compare(
        kind=DateValue,
        check=AtLeast(Date(@units.DateTime::parse("2026-01-01").unwrap())),
      ),
      allow_blank: true,
      prompt: None,
      error: None,
    })
    let validation = only_validation(wb)
    assert_eq(validation.validation_type, "date")
    // Written as an integer, not `46023.0`, so the stored formula is one Excel
    // renders back as a plain date.
    assert_eq(validation.formula1, serial)
  }
}

///|
test "a fractional bound keeps its fraction" {
  let (wb, sheet) = fixture()
  sheet.add_validation({
    at: range("C2", "C9"),
    rule: Compare(kind=Decimal, check=AtLeast(Number(0.5))),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  assert_eq(only_validation(wb).formula1, "0.5")
}

///|
test "the prompt, the error, and the blank policy round-trip" {
  let (wb, sheet) = fixture()
  sheet.add_validation({
    at: range("B2", "B9"),
    rule: List(["a", "b"]),
    allow_blank: false,
    prompt: Some({ title: "Pick", body: "a or b" }),
    error: Some({ title: "Nope", body: "a or b only", style: Warning }),
  })
  let validation = only_validation(wb)
  assert_false(validation.allow_blank)
  assert_eq(validation.prompt_title, Some("Pick"))
  assert_eq(validation.prompt, Some("a or b"))
  assert_true(validation.show_input_message)
  assert_eq(validation.error_title, Some("Nope"))
  assert_eq(validation.error, Some("a or b only"))
  assert_eq(validation.error_style, Some("warning"))
  assert_true(validation.show_error_message)
}

///|
test "every error style round-trips" {
  for
    entry in [
      (@model.ValidationErrorStyle::Stop, "stop"),
      (Warning, "warning"),
      (Information, "information"),
    ] {
    let (style, expected) = entry
    let (wb, sheet) = fixture()
    sheet.add_validation({
      at: range("B2", "B9"),
      rule: List(["a"]),
      allow_blank: true,
      prompt: None,
      error: Some({ title: "t", body: "b", style }),
    })
    assert_eq(only_validation(wb).error_style, Some(expected))
  }
}

///|
test "validations are emitted in declaration order" {
  let (wb, sheet) = fixture()
  sheet.add_validation({
    at: range("A1", "A9"),
    rule: List(["first"]),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  sheet.add_validation({
    at: range("B1", "B9"),
    rule: List(["second"]),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  let validations = reopened.get_data_validations("S")
  assert_eq(validations.length(), 2)
  assert_eq(validations[0].sqref, "A1:A9")
  assert_eq(validations[1].sqref, "B1:B9")
}

///|
test "an external link round-trips with its tooltip" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef::new(col=1, row=1), Text("The report"))
  sheet.add_link(
    @units.CellRef::new(col=1, row=1),
    Url("https://example.com/q3"),
    tip="The Q3 report",
  )
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  guard reopened.get_cell_hyperlink("S", "A1") is Some(link) else {
    fail("expected a hyperlink")
  }
  assert_eq(link.target, "https://example.com/q3")
  assert_true(link.link_type is External)
  assert_eq(link.tooltip, Some("The Q3 report"))
  // A link adds no text of its own; the cell keeps the value it was given.
  assert_eq(reopened.get_cell("S", "A1"), Some("The report"))
}

///|
test "an in-workbook link round-trips as a location" {
  let (wb, sheet) = fixture()
  wb.add_sheet("Summary") |> ignore
  sheet.add_link(@units.CellRef::new(col=2, row=3), Location("Summary!A1"))
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  guard reopened.get_cell_hyperlink("S", "B3") is Some(link) else {
    fail("expected a hyperlink")
  }
  assert_true(link.link_type is Location)
  assert_eq(link.location, Some("Summary!A1"))
  assert_eq(link.tooltip, None)
}
