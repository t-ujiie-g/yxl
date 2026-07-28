// Tests for the decorations a sheet carries. Each builds a model, compiles it,
// and reads it back, so what is asserted is what a real `.xlsx` gives up.

///|
test "notes come back with their text and author" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_comment(at("A1"), "Checked against the ledger.", author="Finance")
  let recovered = only_sheet(wb)
  assert_eq(recovered.comments.length(), 1)
  assert_eq(recovered.comments[0].at.to_a1(), "A1")
  assert_eq(recovered.comments[0].text, "Checked against the ledger.")
  assert_eq(recovered.comments[0].author, Some("Finance"))
}

///|
test "both kinds of link come back" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("site"))
  sheet.set(at("A2"), Text("inside"))
  sheet.add_link(at("A1"), Url("https://example.com"), tip="The site")
  sheet.add_link(at("A2"), Location("Detail!A1"))
  let recovered = only_sheet(wb)
  assert_eq(recovered.links.length(), 2)
  let targets = recovered.links.map(link => link.target)
  assert_true(targets.contains(Url("https://example.com")))
  assert_true(targets.contains(Location("Detail!A1")))
}

///|
test "an inline drop-down comes back as its choices" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_validation({
    at: { top_left: at("B2"), bottom_right: at("B9") },
    rule: List(["Draft", "Sent", "Paid"]),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  let recovered = only_sheet(wb)
  assert_eq(recovered.validations.length(), 1)
  assert_eq(recovered.validations[0].rule, List(["Draft", "Sent", "Paid"]))
  assert_eq(recovered.validations[0].at.to_a1(), "B2:B9")
}

///|
test "a comparing validation comes back with its bounds and its messages" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_validation({
    at: { top_left: at("C2"), bottom_right: at("C9") },
    rule: Compare(kind=Whole, check=Between(Number(1.0), Number(1000.0))),
    allow_blank: false,
    prompt: Some({ title: "Quantity", body: "1 to 1000." }),
    error: Some({ title: "Out of range", body: "Try again.", style: Warning }),
  })
  let recovered = only_sheet(wb).validations[0]
  assert_eq(
    recovered.rule,
    Compare(kind=Whole, check=Between(Number(1.0), Number(1000.0))),
  )
  assert_eq(recovered.allow_blank, false)
  assert_true(recovered.prompt is Some(prompt) && prompt.title == "Quantity")
  assert_true(recovered.error is Some(error) && error.style is Warning)
}

///|
test "a date validation's bounds come back as dates, not as serials" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  let start : @units.DateTime = {
    year: 2026,
    month: 1,
    day: 1,
    hour: 0,
    minute: 0,
    second: 0,
  }
  sheet.add_validation({
    at: { top_left: at("D2"), bottom_right: at("D9") },
    rule: Compare(kind=DateValue, check=AtLeast(Date(start))),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  // The file stores a serial; the spec writes a date, so the epoch has to be
  // carried through to here.
  assert_eq(
    only_sheet(wb).validations[0].rule,
    Compare(kind=DateValue, check=AtLeast(Date(start))),
  )
}

///|
test "a table comes back with its name, style, and toggles" {
  let (wb, sheet) = fixture()
  for column, header in ["Region", "Amount"] {
    sheet.set(@units.CellRef::new(col=column + 1, row=1), Text(header))
  }
  sheet.set(at("A2"), Text("APAC"))
  sheet.set(at("B2"), Number(1.0))
  sheet.add_table({
    at: { top_left: at("A1"), bottom_right: at("B2") },
    name: Some("Sales"),
    style: Some("TableStyleMedium9"),
    banded_rows: true,
    banded_columns: true,
    first_column: false,
    last_column: false,
  })
  let recovered = only_sheet(wb)
  assert_eq(recovered.tables.length(), 1)
  assert_eq(recovered.tables[0].name, Some("Sales"))
  assert_eq(recovered.tables[0].at.to_a1(), "A1:B2")
  assert_eq(recovered.tables[0].banded_columns, true)
}

///|
test "the auto filter comes back as its range" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.set_filter({ top_left: at("A1"), bottom_right: at("C1") })
  assert_true(only_sheet(wb).filter is Some(range) && range.to_a1() == "A1:C1")
}
