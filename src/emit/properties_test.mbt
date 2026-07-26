// Round-trip tests for what the workbook says about itself, and for the notes
// attached to its cells.

///|
/// Document properties with everything set, so a round trip has something to
/// lose on every field.
fn full_properties() -> @model.DocumentProperties {
  {
    title: Some("Quarterly report"),
    subject: Some("Regional sales"),
    author: Some("Finance team"),
    keywords: Some("sales, q3"),
    description: Some("Revenue by region."),
    category: Some("Reports"),
    status: Some("Final"),
    language: Some("en-GB"),
    version: Some("1.2"),
    company: Some("Example Ltd"),
    custom: [],
  }
}

///|
test "every document property round-trips" {
  let (wb, _) = fixture()
  wb.set_properties(full_properties())
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  let core = reopened.get_doc_props()
  assert_eq(core.title, "Quarterly report")
  assert_eq(core.subject, "Regional sales")
  assert_eq(core.creator, "Finance team")
  assert_eq(core.keywords, "sales, q3")
  assert_eq(core.description, "Revenue by region.")
  assert_eq(core.category, "Reports")
  assert_eq(core.content_status, "Final")
  assert_eq(core.language, "en-GB")
  assert_eq(core.version, "1.2")
  // Excel keeps the company apart from the rest, in the application properties.
  assert_eq(reopened.get_app_props().company, "Example Ltd")
}

///|
test "a workbook with no properties writes none" {
  let (wb, _) = fixture()
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  assert_eq(reopened.get_doc_props().title, "")
  assert_eq(reopened.get_custom_props().length(), 0)
}

///|
test "custom properties round-trip with their types and their order" {
  let (wb, _) = fixture()
  wb.set_properties({
    ..@model.DocumentProperties::empty(),
    custom: [
      { name: "Reviewed by", value: Text("J. Smith") },
      // Whole, so it must reach the file as an integer rather than `4210.0`.
      { name: "Cost centre", value: Number(4210.0) },
      { name: "Approved", value: Bool(true) },
      { name: "Margin", value: Number(0.185) },
    ],
  })
  let properties = @xlsx.read(@emit.to_bytes(wb)[:]).get_custom_props()
  assert_eq(properties.length(), 4)
  assert_eq(properties[0].name, "Reviewed by")
  assert_true(properties[0].value is Some(Text("J. Smith")))
  assert_true(properties[1].value is Some(Integer(4210)))
  assert_true(properties[2].value is Some(Boolean(true)))
  assert_true(properties[3].value is Some(Float(0.185)))
}

///|
test "each calc mode round-trips as its OOXML code" {
  for
    entry in [
      (@model.CalcMode::Automatic, "auto"),
      (AutomaticNoTables, "autoNoTable"),
      (Manual, "manual"),
    ] {
    let (mode, code) = entry
    let (wb, _) = fixture()
    wb.set_calc({ mode: Some(mode), on_load: None })
    let calc = @xlsx.read(@emit.to_bytes(wb)[:]).get_calc_props()
    assert_eq(calc.calc_mode, Some(code))
  }
}

///|
test "a recalculation on open round-trips on its own" {
  let (wb, _) = fixture()
  wb.set_calc({ mode: None, on_load: Some(true) })
  let calc = @xlsx.read(@emit.to_bytes(wb)[:]).get_calc_props()
  assert_eq(calc.full_calc_on_load, Some(true))
  assert_eq(calc.calc_mode, None)
}

///|
test "a note round-trips against its cell, which keeps its own value" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef::new(col=2, row=2), Number(2400000.0))
  sheet.add_comment(
    @units.CellRef::new(col=2, row=2),
    "Restated after the Q3 review.",
    author="Finance",
  )
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  let comments = reopened.get_comments("S")
  assert_eq(comments.length(), 1)
  assert_eq(comments[0].cell, "B2")
  assert_eq(comments[0].text, "Restated after the Q3 review.")
  assert_eq(comments[0].author, "Finance")
  assert_eq(reopened.get_cell("S", "B2"), Some("2400000"))
}

///|
/// A note always carries an author in the file, so leaving one out does not
/// omit it — the backend writes its generic default, which is what the model
/// documents.
test "a note with no author still names one" {
  let (wb, sheet) = fixture()
  sheet.add_comment(@units.CellRef::new(col=1, row=1), "No author here.")
  let comments = @xlsx.read(@emit.to_bytes(wb)[:]).get_comments("S")
  assert_eq(comments[0].text, "No author here.")
  assert_true(comments[0].author != "")
}

///|
test "notes are emitted in declaration order" {
  let (wb, sheet) = fixture()
  sheet.add_comment(@units.CellRef::new(col=3, row=3), "third")
  sheet.add_comment(@units.CellRef::new(col=1, row=1), "first")
  let comments = @xlsx.read(@emit.to_bytes(wb)[:]).get_comments("S")
  assert_eq(comments[0].cell, "C3")
  assert_eq(comments[1].cell, "A1")
}
