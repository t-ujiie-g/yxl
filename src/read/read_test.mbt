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
test "the reader seam works through the trait, not only the shorthand" {
  // ADR-002's whole claim is that the backend sits behind an interface, and
  // ADR-017 mirrors it for this direction. `from_bytes` is a convenience over
  // the trait, so exercising only that would leave the seam itself unproven.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  let reader = @read.MbtexcelReader::new()
  let recovered = reader.read(@emit.to_bytes(wb))
  assert_eq(recovered.workbook.sheets.length(), 1)
  assert_eq(cell_at(recovered.workbook.sheets[0], "A1"), Some(Text("Region")))
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
  let italic : @model.Font = { ..@model.Font::empty(), italic: Some(true) }
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
    font: Some({ ..@model.Font::empty(), bold: Some(true) }),
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
test "a built-in number format id comes back as the code Excel writes for it" {
  // Excel does not write a `numFmt` element for a format it recognizes as one
  // of its own: a cell formatted `#,##0_);(#,##0)` is stored as id 37 and the
  // code has to be supplied from the table. ECMA-376 §18.8.30 prints a space
  // where Office puts `_)` (MS-OI29500 §2.1.601), so reading the standard's
  // spelling back would quietly widen the digits by one and misalign the
  // column against the source workbook.
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("S")
  backend.set_cell_int("S", "A1", 1234)
  let accounting = backend.new_style(@xlsx.Style::builtin_number_format(37))
  backend.set_cell_style("S", "A1", accounting)
  let recovered = @read.from_bytes(backend.write_to_buffer())
  let cell = recovered.workbook.sheets[0].cells[0]
  assert_true(
    cell.style is Some(style) && style.number_format is Some("#,##0_);(#,##0)"),
  )
}

///|
test "a theme or palette colour resolves to the RGB it stands for" {
  // A real workbook's headings are almost all theme colours, so leaving these
  // as a loss made an extracted spec compile to a differently-coloured workbook
  // (#50). The theme and the palette both live in the file being read, so the
  // resolution is a lookup, not a guess.
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("S")
  for reference in ["A1", "A2", "A3"] {
    backend.set_cell_str("S", reference, "x")
  }
  // Theme 4 is accent1 in the order the file numbers them, which the default
  // theme paints FF4F81BD.
  let themed = backend.new_style(
    @xlsx.Style::font(@xlsx.Font::with_values(color_theme=4)),
  )
  backend.set_cell_style("S", "A1", themed)
  // The same colour, lightened: a tint is applied in HLS, not by scaling the
  // channels, so a wrong implementation still lands somewhere plausible.
  let tinted = backend.new_style(
    @xlsx.Style::font(@xlsx.Font::with_values(color_theme=4, color_tint=0.4)),
  )
  backend.set_cell_style("S", "A2", tinted)
  let indexed = backend.new_style(
    @xlsx.Style::font(@xlsx.Font::with_values(color_indexed=10)),
  )
  backend.set_cell_style("S", "A3", indexed)
  let recovered = @read.from_bytes(backend.write_to_buffer())
  let colors = []
  for cell in recovered.workbook.sheets[0].cells {
    guard cell.style is Some(style) && style.font is Some(font) else {
      continue
    }
    colors.push(font.color.map(color => color.hex()))
  }
  assert_eq(colors, [Some("FF4F81BD"), Some("FF95B3D7"), Some("FFFF0000")])
  // Nothing was reported lost: the whole point is that these are recoverable.
  assert_false(recovered.dropped.iter().any(note => note.contains("colour")))
}

///|
test "a theme index the workbook does not define is named, not guessed at" {
  // The theme in the file runs `lt1, dk1, lt2, dk2, accent1..6`; the hyperlink
  // pair sits past the end of it. A colour there is a real loss and the
  // extract-to-spec checklist tells a reader to act on the note, so the note
  // has to be there.
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("S")
  backend.set_cell_str("S", "A1", "linked")
  let hyperlink = backend.new_style(
    @xlsx.Style::font(@xlsx.Font::with_values(color_theme=10)),
  )
  backend.set_cell_style("S", "A1", hyperlink)
  let recovered = @read.from_bytes(backend.write_to_buffer())
  assert_true(
    recovered.dropped
    .iter()
    .any(note => note.contains("the workbook does not define")),
  )
}

///|
test "a shared formula comes back as the range that declared it" {
  let (wb, sheet) = fixture()
  sheet.set(at("B2"), Number(2.0))
  sheet.set(at("B3"), Number(3.0))
  sheet.set(at("B4"), Number(4.0))
  sheet.add_formula({
    at: @model.CellRange::parse("C2:C4").unwrap(),
    formula: "B2*2",
  })
  let recovered = only_sheet(wb)
  assert_eq(recovered.formulas.length(), 1)
  assert_eq(recovered.formulas[0].at.to_a1(), "C2:C4")
  assert_eq(recovered.formulas[0].formula, "B2*2")
  // Folded into the range, so the cells it covers are not also written out —
  // a spec saying both would not compile.
  assert_eq(cell_at(recovered, "C2"), None)
  assert_eq(cell_at(recovered, "C3"), None)
}

///|
test "a shared formula's followers are translated where the range cannot fold" {
  // A `formulas:` range carries no styling, so a styled calculation column has
  // to come back cell by cell. Each follower stores no text of its own; before
  // it was translated, the cell simply vanished from the spec and its
  // calculation with it (#52).
  let (wb, sheet) = fixture()
  sheet.set(at("B2"), Number(2.0))
  sheet.set(at("B3"), Number(3.0))
  sheet.set_column_band(first=3, last=3, style={
    ..@model.Style::empty(),
    font: Some({ ..@model.Font::empty(), bold: Some(true) }),
  })
  sheet.add_formula({
    at: @model.CellRange::parse("C2:C3").unwrap(),
    formula: "B2*2",
  })
  let recovered = only_sheet(wb)
  assert_eq(recovered.formulas.length(), 0)
  assert_eq(
    cell_at(recovered, "C2"),
    Some(Formula(formula="B2*2", cached=None)),
  )
  // The follower's relative reference moved with it, the way Excel shifts it.
  assert_eq(
    cell_at(recovered, "C3"),
    Some(Formula(formula="B3*2", cached=None)),
  )
}

///|
test "a cell that is a style and nothing else comes back" {
  // A real workbook has these by the hundred thousand — the shaded box, the
  // ruled table edge, the blank half of a merged heading — and dropping them
  // redrew it (#48).
  let backend = @xlsx.Workbook::new()
  let _ = backend.new_sheet("S")
  backend.set_cell_str("S", "A1", "hello")
  let shaded = backend.new_style(
    @xlsx.Style::fill(@xlsx.Fill::solid("FFFF0000")),
  )
  backend.set_cell_style("S", "B2", shaded)
  let sheet = @read.from_bytes(backend.write_to_buffer()).workbook.sheets[0]
  assert_eq(cell_at(sheet, "B2"), Some(Blank))
  for cell in sheet.cells {
    if cell.pos.to_a1() == "B2" {
      assert_true(cell.style is Some(style) && style.fill is Some(_))
    }
  }
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

///|
test "the workbook's own keys come back" {
  let wb = @model.Workbook::new(default_font="Georgia")
  wb.add_sheet("S").set(at("A1"), Text("x"))
  wb.add_defined_name("tax_rate", Number(0.085))
  wb.add_defined_name("company", Text("Acme Corp"))
  wb.add_defined_name("subtotal", Formula(formula="SUM(S!A1:A9)", cached=None))
  wb.set_properties({
    ..@model.DocumentProperties::empty(),
    title: Some("Regional summary"),
    author: Some("Finance"),
    company: Some("Example Ltd"),
    custom: [{ name: "Cost centre", value: Number(4210.0) }],
  })
  wb.set_calc({ mode: Some(Manual), on_load: Some(true) })
  let recovered = round_trip(wb).workbook
  assert_eq(recovered.default_font, Some("Georgia"))
  assert_eq(recovered.defined_names.length(), 3)
  let names = recovered.defined_names.map(defined => defined.name)
  assert_true(names.contains("tax_rate"))
  assert_true(names.contains("company"))
  // Excel's own bookkeeping lives in the same table and is not the spec's.
  for defined in recovered.defined_names {
    assert_true(!defined.name.has_prefix("_xlnm."))
  }
  assert_true(
    recovered.properties is Some(properties) &&
    properties.title is Some("Regional summary") &&
    properties.company is Some("Example Ltd") &&
    properties.custom.length() == 1,
  )
  assert_true(
    recovered.calc is Some(calc) &&
    calc.mode is Some(Manual) &&
    calc.on_load is Some(true),
  )
}

///|
test "a defined name comes back as the kind of thing it refers to" {
  let wb = @model.Workbook::new()
  wb.add_sheet("S").set(at("A1"), Text("x"))
  wb.add_defined_name("number", Number(0.085))
  wb.add_defined_name("text", Text("Acme Corp"))
  wb.add_defined_name("flag", Bool(true))
  wb.add_defined_name("formula", Formula(formula="SUM(S!A1:A9)", cached=None))
  let by_name : Map[String, @model.CellValue] = Map([])
  for defined in round_trip(wb).workbook.defined_names {
    by_name[defined.name] = defined.refers_to
  }
  assert_eq(by_name.get("number"), Some(Number(0.085)))
  assert_eq(by_name.get("text"), Some(Text("Acme Corp")))
  assert_eq(by_name.get("flag"), Some(Bool(true)))
  assert_eq(
    by_name.get("formula"),
    Some(Formula(formula="SUM(S!A1:A9)", cached=None)),
  )
}

///|
test "sheet protection comes back, without the password it cannot know" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_protection({
    ..@model.SheetProtection::new(),
    password: Some("secret"),
    sort: true,
    auto_filter: true,
  })
  let recovered = only_sheet(wb)
  assert_true(recovered.protection is Some(_))
  guard recovered.protection is Some(protection) else { return }
  assert_eq(protection.sort, true)
  assert_eq(protection.auto_filter, true)
  // The file keeps a hash, not the word; a spec that invented one would look
  // protected while opening to anyone.
  assert_eq(protection.password, None)
}

///|
test "an unprotected sheet comes back unprotected" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  assert_eq(only_sheet(wb).protection, None)
}

///|
test "a very hidden sheet is told from a merely hidden one" {
  let wb = @model.Workbook::new()
  wb.add_sheet("Visible").set(at("A1"), Text("x"))
  wb.add_sheet("Hidden", visibility=Hidden) |> ignore
  wb.add_sheet("Locked", visibility=VeryHidden) |> ignore
  let recovered = round_trip(wb).workbook
  assert_true(recovered.sheets[1].visibility is Hidden)
  assert_true(recovered.sheets[2].visibility is VeryHidden)
}
