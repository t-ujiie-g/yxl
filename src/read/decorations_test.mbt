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

///|
/// A conditional format over `A1:A9` with `rule`, drawn in a red fill.
fn conditional(
  rule : @model.ConditionalRule,
  style~ : Bool,
) -> @model.Sheet raise {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(10.0))
  sheet.add_conditional_format({
    at: { top_left: at("A1"), bottom_right: at("A9") },
    rule,
    style: if style {
      Some({
        ..@model.Style::empty(),
        fill: Some({ color: @units.Color::parse("FFC7CE").unwrap() }),
      })
    } else {
      None
    },
    stop_if_true: false,
  })
  only_sheet(wb)
}

///|
test "every conditional rule the schema names comes back as itself" {
  // The backend hands all of these back as one flat options record, so the only
  // way to know the translation is right is to send each kind through it.
  for
    rule in [
      @model.CellIs(GreaterThan(Number(15.0))),
      CellIs(Between(Number(1.0), Number(10.0))),
      CellIs(Equal(Text("Paid"))),
      Formula("A1>0"),
      Text(match_=Contains, value="urgent"),
      Text(match_=BeginsWith, value="ORD-"),
      Rank(count=3, bottom=false, percent=false),
      Rank(count=10, bottom=true, percent=true),
      Duplicate,
      Unique,
    ] {
    assert_eq(
      (rule, conditional(rule, style=true).conditional_formats[0].rule),
      (rule, rule),
    )
  }
}

///|
test "the rules that draw their own appearance come back too" {
  let red = @units.Color::parse("F8696B").unwrap()
  let green = @units.Color::parse("63BE7B").unwrap()
  let amber = @units.Color::parse("FFEB84").unwrap()
  for
    rule in [
      @model.ColorScale(low=red, middle=None, high=green),
      ColorScale(low=red, middle=Some(amber), high=green),
      DataBar(color=green, bar_only=false),
      DataBar(color=green, bar_only=true),
      IconSet(style="3Arrows", reverse=false, icons_only=false),
      IconSet(style="5Rating", reverse=true, icons_only=true),
    ] {
    assert_eq(
      (rule, conditional(rule, style=false).conditional_formats[0].rule),
      (rule, rule),
    )
  }
}

///|
test "a conditional format keeps its own look and its stop flag" {
  let recovered = conditional(Duplicate, style=true).conditional_formats[0]
  assert_true(
    recovered.style is Some(style) &&
    style.fill is Some(fill) &&
    fill.color.hex() == "FFC7CE",
  )
  assert_eq(recovered.stop_if_true, false)
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(1.0))
  sheet.add_conditional_format({
    at: { top_left: at("A1"), bottom_right: at("A9") },
    rule: Unique,
    style: Some({
      ..@model.Style::empty(),
      fill: Some({ color: @units.Color::parse("FFC7CE").unwrap() }),
    }),
    stop_if_true: true,
  })
  assert_eq(only_sheet(wb).conditional_formats[0].stop_if_true, true)
}

///|
test "a highlighting rule with no expressible style is dropped and named" {
  // The real case is a dxf holding only what the schema cannot say — a
  // theme-indexed colour recovers as no style at all — and writing the rule
  // out anyway makes a spec the loader refuses, which is how a real workbook
  // failed the extraction's verify pass. Emitting `style: None` reaches the
  // reader the same way.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(1.0))
  sheet.add_conditional_format({
    at: { top_left: at("A1"), bottom_right: at("A9") },
    rule: Unique,
    style: None,
    stop_if_true: false,
  })
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets[0].conditional_formats, [])
  assert_true(
    recovered.dropped
    .iter()
    .any(note => note.contains("would match cells and change nothing")),
  )
}

///|
test "a style on a self-drawing rule is dropped and named, the rule kept" {
  // The loader refuses a 'style' on a scale, a bar, or an icon set, so one
  // recovered from a file has nowhere to go; the rule itself is fine. Only a
  // foreign file can put a dxfId on a data bar — the backend writes that
  // attribute for highlighting rules alone — so the rule is injected as the
  // raw cfRule such a file would carry.
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("S")
  backend.set_cell_int("S", "A1", 1)
  let dxf = backend.new_conditional_style(
    @xlsx.Style::fill(@xlsx.Fill::solid("FFC7CE")),
  )
  guard backend.sheet("S") is Some(source)
  source.conditional_formats.push(
    "<conditionalFormatting sqref=\"A1:A9\"><cfRule type=\"dataBar\" dxfId=\"\{dxf}\" priority=\"1\"><dataBar><cfvo type=\"min\"/><cfvo type=\"max\"/><color rgb=\"FF63BE7B\"/></dataBar></cfRule></conditionalFormatting>",
  )
  let recovered = @read.from_bytes(backend.write_to_buffer())
  guard recovered.workbook.sheets[0].conditional_formats
    is [{ rule: DataBar(..), style: None, .. }]
  assert_true(
    recovered.dropped
    .iter()
    .any(note => note.contains("draws its own appearance")),
  )
}
