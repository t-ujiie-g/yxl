///|
fn page(
  area? : String,
  orientation? : @model.Orientation,
  margins? : @model.PageMargins,
  scale? : @model.PageScale,
  header? : String,
  footer? : String,
  breaks~ : Array[String] = [],
) -> @model.PageSetup {
  {
    area: area.bind(@model.CellRange::parse),
    orientation,
    margins,
    scale,
    header,
    footer,
    breaks: breaks.map(at),
    title_rows: None,
  }
}

///|
test "print setup comes back per sheet" {
  let wb = @model.Workbook()
  let first = wb.add_sheet("Q1 Sales")
  first.set(at("A1"), Text("x"))
  let setup = page(
    area="A1:C3",
    orientation=Landscape,
    margins={
      top: Some(1.0),
      bottom: None,
      left: None,
      right: Some(0.5),
      header: None,
      footer: None,
    },
    scale=Percent(80),
    header="&CQuarterly",
    footer="&LPage &P of &N",
    breaks=["A21", "D1"],
  )
  first.set_page_setup(setup)
  // A sheet printing at Excel's defaults after one that does not: no leak.
  wb.add_sheet("Plain").set(at("A1"), Text("y"))
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets[0].page, Some(setup))
  assert_eq(recovered.workbook.sheets[1].page, None)
  assert_eq(recovered.dropped, [])
}

///|
test "fit-to-pages comes back as a fit, not a percentage" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_page_setup(page(scale=Fit(width=1, height=0)))
  assert_eq(only_sheet(wb).page, Some(page(scale=Fit(width=1, height=0))))
}

///|
test "a break on both axes comes back as one break per axis" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_page_setup(page(breaks=["C5"]))
  assert_eq(only_sheet(wb).page, Some(page(breaks=["A5", "C1"])))
}

///|
test "a sheet that prints at Excel's defaults says nothing about printing" {
  // A note on every sheet would be noise that hides the real losses.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets[0].page, None)
  assert_eq(recovered.dropped, [])
}

///|
test "print settings the spec has no word for are named" {
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("S")
  backend.set_cell_str("S", "A1", "x")
  backend.set_page_layout(
    "S",
    Some(
      @xlsx.PageLayoutOptions::with_values(
        size=9,
        orientation="landscape",
        black_and_white=true,
      ),
    ),
  )
  let recovered = @read.from_bytes(backend.write_to_buffer())
  assert_eq(
    recovered.workbook.sheets[0].page,
    Some(page(orientation=Landscape)),
  )
  assert_true(noted(recovered, "paper size"))
  assert_true(noted(recovered, "black-and-white"))
}

///|
test "print titles come back as the rows they repeat" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  let setup = { ..page(), title_rows: Some({ first: 1, last: 2, }), }
  sheet.set_page_setup(setup)
  assert_eq(only_sheet(wb).page, Some(setup))
}
