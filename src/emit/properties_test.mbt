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
  let reopened = reopen(wb)
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
  let reopened = reopen(wb)
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
  let properties = reopen(wb).get_custom_props()
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
    let calc = reopen(wb).get_calc_props()
    assert_eq(calc.calc_mode, Some(code))
  }
}

///|
test "a recalculation on open round-trips on its own" {
  let (wb, _) = fixture()
  wb.set_calc({ mode: None, on_load: Some(true) })
  let calc = reopen(wb).get_calc_props()
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
  let reopened = reopen(wb)
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
  let comments = reopen(wb).get_comments("S")
  assert_eq(comments[0].text, "No author here.")
  assert_eq(comments[0].author, "Author")
}

///|
test "notes are emitted in declaration order" {
  let (wb, sheet) = fixture()
  sheet.add_comment(@units.CellRef::new(col=3, row=3), "third")
  sheet.add_comment(@units.CellRef::new(col=1, row=1), "first")
  let comments = reopen(wb).get_comments("S")
  assert_eq(comments[0].cell, "C3")
  assert_eq(comments[1].cell, "A1")
}

///|
test "sheet protection round-trips as allowances, not as locks" {
  let (wb, sheet) = fixture()
  sheet.set_protection({
    ..@model.SheetProtection::new(),
    sort: true,
    format_cells: true,
    select_locked_cells: false,
  })
  let reopened = reopen(wb)
  let protection = reopened.get_sheet_protection("S")
  // What was granted comes back granted, and what was not stays blocked — the
  // backend's options are allowances, as the model's are, and OOXML's
  // attributes are the inverse of both.
  assert_true(protection.sort)
  assert_true(protection.format_cells)
  assert_false(protection.select_locked_cells)
  assert_true(protection.select_unlocked_cells)
  assert_false(protection.format_rows)
}

///|
test "an unprotected sheet stays unprotected" {
  let (wb, _) = fixture()
  let protection = reopen(wb).get_sheet_protection("S")
  // Nothing granted and nothing blocked: the sheet carries no protection at all.
  assert_false(protection.sort)
  assert_false(protection.select_locked_cells)
}

///|
/// A password does not come back out: Excel stores a hash rather than the word,
/// and the backend's reader does not surface it. What can be asserted is that
/// adding one disturbs nothing else — the allowances still say what they said.
/// That the hash reaches the file (`password="F533"` in `sheetProtection`) was
/// read out of the XML by hand; asserting it here would need a zip reader the
/// test packages do not have.
test "a sheet password leaves the allowances alone" {
  let (wb, sheet) = fixture()
  sheet.set_protection({
    ..@model.SheetProtection::new(),
    sort: true,
    password: Some("s3cret"),
  })
  let protection = reopen(wb).get_sheet_protection("S")
  assert_true(protection.sort)
  assert_true(protection.select_locked_cells)
  assert_false(protection.format_cells)
}

///|
test "cell protection round-trips through the style" {
  let (wb, sheet) = fixture()
  let unlocked : @model.Style = {
    ..@model.Style::empty(),
    protection: Some({ locked: Some(false), hidden: None }),
  }
  sheet.set(@units.CellRef::new(col=1, row=1), Number(1.0), style=unlocked)
  let reopened = reopen(wb)
  guard reopened.get_cell_style("S", "A1") is Some(id) else {
    fail("expected a style on A1")
  }
  guard reopened.get_style(id).protection is Some(protection) else {
    fail("expected the style to carry protection")
  }
  assert_eq(protection.locked, Some(false))
}

///|
/// Excel locks every cell and hides no formula by default, so a style asking
/// for exactly that changes nothing — and the backend gives us only one seed
/// slot, which such a style must not occupy.
test "a style asking only for Excel's defaults leaves the seed slot free" {
  let (wb, sheet) = fixture()
  let default_protection : @model.Style = {
    ..@model.Style::number_format("0.0%"),
    protection: Some({ locked: Some(true), hidden: Some(false) }),
  }
  sheet.set(
    @units.CellRef::new(col=1, row=1),
    Number(0.085),
    style=default_protection,
  )
  // Would raise if the redundant protection had taken the number format's place.
  let reopened = reopen(wb)
  assert_true(reopened.get_cell_style("S", "A1") is Some(_))
  // The seed slot went to the number format the spec set, which still formats
  // the value on read-back.
  assert_eq(reopened.get_cell_value("S", "A1", raw=false), Some("8.5%"))
}

///|
/// The backend seeds a style from one attribute and layers the rest with
/// `with_*` builders, and it has no `with_protection` — so protection can only
/// be the seed, and a style needing a number format as well cannot be built.
/// Refused with something the author can act on rather than silently dropped.
test "a style cannot carry both a number format and real cell protection" {
  let (wb, sheet) = fixture()
  let clash : @model.Style = {
    ..@model.Style::number_format("0.0%"),
    protection: Some({ locked: Some(false), hidden: None }),
  }
  sheet.set(@units.CellRef::new(col=1, row=1), Number(0.085), style=clash)
  let message = try {
    @emit.to_bytes(wb) |> ignore
    None
  } catch {
    @diag.EmitError(diagnostic) => Some(diagnostic.render())
  }
  guard message is Some(message) else { fail("expected an emit error") }
  assert_true(
    message.has_prefix(
      "the Excel backend cannot put a number format and cell protection in one style",
    ),
  )
  // And it names the format, so the author can find the style that clashed.
  assert_true(message.contains("'0.0%'"))
}

///|
test "workbook protection round-trips" {
  let (wb, _) = fixture()
  wb.set_protection({ structure: true, windows: false, password: None })
  let reopened = reopen(wb)
  // The backend keeps its `WorkbookProtection` abstract, so the assertion is
  // that one exists at all; what it says is checked in the file itself.
  assert_true(reopened.workbook_protection is Some(_))
}
