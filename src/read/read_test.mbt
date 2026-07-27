// Tests for the reader seam. Every one builds a model, compiles it with `emit`,
// and reads the bytes back — so what is asserted is what survives a real
// `.xlsx`, not what survives a fixture somebody wrote to match.

///|
/// Compile a workbook and read it back.
fn round_trip(wb : @model.Workbook) -> @read.Recovered raise {
  @read.from_bytes(@emit.to_bytes(wb))
}

///|
/// The sole sheet of a round-tripped workbook.
fn only_sheet(wb : @model.Workbook) -> @model.Sheet raise {
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets.length(), 1)
  recovered.workbook.sheets[0]
}

///|
/// The cell at `reference`, or `None` where the sheet has none.
fn cell_at(sheet : @model.Sheet, reference : String) -> @model.CellValue? {
  for cell in sheet.cells {
    if cell.pos.to_a1() == reference {
      return Some(cell.value)
    }
  }
  None
}

///|
/// A one-sheet workbook, plus the sheet.
fn fixture() -> (@model.Workbook, @model.Sheet) {
  let wb = @model.Workbook::new()
  (wb, wb.add_sheet("S"))
}

///|
fn at(reference : String) -> @units.CellRef {
  @units.CellRef::parse_a1(reference).unwrap()
}

///|
test "the values a cell can hold come back as themselves" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.set(at("A2"), Number(2400000.0))
  sheet.set(at("A3"), Bool(true))
  sheet.set(at("A4"), Error("#DIV/0!"))
  let recovered = only_sheet(wb)
  assert_eq(cell_at(recovered, "A1"), Some(Text("Region")))
  assert_eq(cell_at(recovered, "A2"), Some(Number(2400000.0)))
  assert_eq(cell_at(recovered, "A3"), Some(Bool(true)))
  assert_eq(cell_at(recovered, "A4"), Some(Error("#DIV/0!")))
}

///|
test "a formula comes back without its cached result" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Formula(formula="SUM(B1:B9)", cached=Some(Number(42.0))))
  // The cache is a display value Excel recomputes on open, and the backend hands
  // it back as text whatever it was; carrying it would put a stale number in the
  // spec that reads like a claim about the formula's answer.
  assert_eq(
    cell_at(only_sheet(wb), "A1"),
    Some(Formula(formula="SUM(B1:B9)", cached=None)),
  )
}

///|
test "plain text does not come back as a one-run rich text" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  // The backend answers `get_cell_rich_text` for every shared string, so this is
  // the difference between a readable spec and one where every label is three
  // lines of `rich:`.
  assert_eq(cell_at(only_sheet(wb), "A1"), Some(Text("Region")))
}

///|
test "text that really does mix fonts comes back as runs" {
  let (wb, sheet) = fixture()
  let italic : @model.Font = {
    bold: None,
    italic: Some(true),
    underline: None,
    strike: None,
    size: None,
    name: None,
    color: None,
  }
  sheet.set(
    at("A1"),
    RichText([
      { text: "plain ", font: None },
      { text: "italic", font: Some(italic) },
    ]),
  )
  let recovered = cell_at(only_sheet(wb), "A1")
  assert_true(recovered is Some(RichText(runs)) && runs.length() == 2)
  guard recovered is Some(RichText(runs)) else { return }
  assert_eq(runs[0].text, "plain ")
  assert_eq(runs[1].text, "italic")
  assert_true(runs[1].font is Some(font) && font.italic is Some(true))
}

///|
test "a style comes back, and cells that shared one still share it" {
  let (wb, sheet) = fixture()
  let header : @model.Style = {
    ..@model.Style::empty(),
    font: Some({
      bold: Some(true),
      italic: None,
      underline: None,
      strike: None,
      size: None,
      name: None,
      color: None,
    }),
    fill: Some({ color: @units.Color::parse("1F3864").unwrap() }),
  }
  sheet.set(at("A1"), Text("Region"), style=header)
  sheet.set(at("B1"), Text("Revenue"), style=header)
  let recovered = only_sheet(wb)
  let styles = []
  for cell in recovered.cells {
    if cell.style is Some(style) {
      styles.push(style)
    }
  }
  assert_eq(styles.length(), 2)
  // Equal, which is what makes them intern to one `defs.styles` entry — the
  // backend keeps the sharing even though it lost the name.
  assert_eq(styles[0], styles[1])
  assert_true(styles[0].font is Some(font) && font.bold is Some(true))
  assert_true(styles[0].fill is Some(_))
}

///|
test "a number format comes back as its code" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(0.085), style={
    ..@model.Style::empty(),
    number_format: Some("0.0%"),
  })
  let recovered = only_sheet(wb)
  assert_true(
    recovered.cells[0].style is Some(style) &&
    style.number_format is Some("0.0%"),
  )
}

///|
test "merges come back" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Title"))
  sheet.merge(at("A1"), at("C1"))
  let recovered = only_sheet(wb)
  assert_eq(recovered.merges.length(), 1)
  assert_eq(recovered.merges[0].to_a1(), "A1:C1")
}

///|
test "column bands come back, and adjacent equal ones collapse into a run" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_column_band(first=2, last=3, width=12.0)
  let recovered = only_sheet(wb)
  assert_eq(recovered.columns.length(), 1)
  assert_eq(recovered.columns[0].first, 2)
  assert_eq(recovered.columns[0].last, 3)
  assert_eq(recovered.columns[0].size, Some(12.0))
}

///|
test "a band beyond the last populated cell is still found" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  // Column E holds nothing, so a scan of the used range would never see it —
  // which is why the records are read rather than the rectangle.
  sheet.set_column_band(first=5, last=5, hidden=true, outline_level=1)
  let recovered = only_sheet(wb)
  assert_eq(recovered.columns.length(), 1)
  assert_eq(recovered.columns[0].first, 5)
  assert_eq(recovered.columns[0].hidden, Some(true))
  assert_eq(recovered.columns[0].outline_level, Some(1))
}

///|
test "row bands come back" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_row_band(first=1, last=1, height=28.0)
  let recovered = only_sheet(wb)
  assert_eq(recovered.rows.length(), 1)
  assert_eq(recovered.rows[0].size, Some(28.0))
}

///|
test "frozen panes, gridlines, and the tab colour come back" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_panes(Freeze(at("B3")))
  sheet.set_gridlines(false)
  sheet.set_tab_color(@units.Color::parse("1F77B4").unwrap())
  let recovered = only_sheet(wb)
  assert_eq(recovered.panes, Some(Freeze(at("B3"))))
  assert_eq(recovered.gridlines, Some(false))
  assert_true(recovered.tab_color is Some(color) && color.hex() == "1F77B4")
}

///|
test "sheet names, order, hiding, and the active tab come back" {
  let wb = @model.Workbook::new()
  let first = wb.add_sheet("Summary")
  first.set(at("A1"), Text("x"))
  wb.add_sheet("Hidden", visibility=Hidden).set(at("A1"), Text("y"))
  wb.add_sheet("Detail").set(at("A1"), Text("z"))
  wb.set_active_sheet("Detail")
  let recovered = round_trip(wb).workbook
  assert_eq(recovered.sheets.map(sheet => sheet.name), [
    "Summary", "Hidden", "Detail",
  ])
  assert_true(recovered.sheets[1].visibility is Hidden)
  assert_eq(recovered.active_sheet, Some("Detail"))
}

///|
test "the 1904 date system comes back" {
  let wb = @model.Workbook::new(date_system=Date1904)
  wb.add_sheet("S").set(at("A1"), Number(1.0))
  assert_true(round_trip(wb).workbook.date_system is Date1904)
}

///|
test "an empty workbook reads as an empty workbook" {
  let wb = @model.Workbook::new()
  wb.add_sheet("S") |> ignore
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets.length(), 1)
  assert_eq(recovered.workbook.sheets[0].cells.length(), 0)
  assert_eq(recovered.dropped, [])
}

///|
test "bytes that are not a workbook are a diagnostic, not a crash" {
  let outcome = try {
    @read.from_bytes(b"not a zip, let alone a workbook") |> ignore
    None
  } catch {
    @diag.ReadError(d) => Some(d.render())
  }
  assert_true(outcome is Some(_))
}
