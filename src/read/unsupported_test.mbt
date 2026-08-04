// Tests for the features the reader knows about and does not bring back.
//
// These are the easiest notes in the codebase to lose: they are produced by
// code that runs *because* nothing else ran, so deleting the note deletes the
// only evidence the feature existed. Each one below therefore asserts both
// halves — the loss happened, and it was said aloud — and one asserts the
// opposite, that a workbook without the feature stays quiet.

///|
/// The minimal `chartSpace` part the backend will store for a chart sheet.
fn chart_xml() -> String {
  (
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:layout/><c:barChart><c:barDir val="col"/></c:barChart></c:plotArea></c:chart></c:chartSpace>
  )
}

///|
test "a chart sheet is skipped and named, not walked as a grid" {
  // `get_sheet_list` names a chart sheet alongside the worksheets while every
  // per-sheet accessor answers `SheetNotFound` for it, so reading one used to
  // fail the whole extraction with the backend's own error and nothing to act
  // on. Right-clicking a chart and choosing "Move to new sheet" is all it takes
  // to make a workbook like this, so it is not an exotic case.
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("Data")
  backend.set_cell_str("Data", "A1", "Region")
  let _ = backend.add_chart_sheet("Picture", chart_xml())
  let recovered = @read.from_bytes(backend.write_to_buffer())
  // The grid sheet came through; the chart sheet did not become an empty one,
  // which would claim a data tab the workbook does not have.
  assert_eq(recovered.workbook.sheets.map(sheet => sheet.name), ["Data"])
  assert_true(
    recovered.dropped
    .iter()
    .any(note => note.contains("chart sheet rather than a grid")),
  )
}

///|
test "a chart on a sheet is named rather than dropped in silence" {
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("S")
  backend.set_cell_str("S", "A1", "Region")
  backend.set_cell_int("S", "B1", 1)
  guard! backend.sheet("S") is Some(source)
  source.add_chart("D2", chart_xml())
  let recovered = @read.from_bytes(backend.write_to_buffer())
  assert_eq(recovered.workbook.sheets[0].charts, [])
  assert_true(
    recovered.dropped
    .iter()
    .any(note => note.contains("a chart, which the Excel backend")),
  )
}

///|
test "print setup is named rather than dropped in silence" {
  // Detected off the worksheet's own `page_layout` field rather than through
  // `page_layout_with_defaults`, which aliases a module-level default — asking
  // that would make one sheet's answer leak into every later sheet's, and this
  // note would then fire on sheets that print at Excel's defaults.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_page_setup({
    area: @model.CellRange::parse("A1:C3"),
    orientation: Some(@model.Landscape),
    margins: None,
    scale: None,
    header: None,
    footer: None,
    breaks: [],
  })
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets[0].page, None)
  assert_true(
    recovered.dropped.iter().any(note => note.contains("print setup")),
  )
}

///|
test "a sheet that prints at Excel's defaults says nothing about printing" {
  // The other half, and the one that decides whether these notes are worth
  // reading: a note on every sheet of every workbook is noise, and noise is
  // what makes a reader skip the list that carries the real losses.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  let recovered = round_trip(wb)
  assert_eq(recovered.dropped, [])
}
