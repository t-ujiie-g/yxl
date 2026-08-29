///|
/// Whether any note says this.
fn noted(recovered : @read.Recovered, fragment : String) -> Bool {
  recovered.dropped.iter().any(note => note.contains(fragment))
}

///|
/// A control with nothing set but its position and kind.
fn bare_control(
  kind : @model.FormControlKind,
  at_ref : String,
) -> @model.FormControl {
  {
    at: at(at_ref),
    kind,
    text: None,
    checked: None,
    link: None,
    width: None,
    height: None,
    min: None,
    max: None,
    step: None,
    page: None,
    value: None,
    horizontal: None,
  }
}

///|
test "every kind of form control comes back as itself" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  let kinds : Array[@model.FormControlKind] = [
    Button,
    CheckBox,
    OptionButton,
    ScrollBar,
    SpinButton,
    GroupBox,
    Label,
  ]
  let mut row = 1
  for kind in kinds {
    sheet.add_control({ ..bare_control(kind, "D\{row}"), text: Some("Go"), })
    row += 2
  }
  let recovered = only_sheet(wb)
  assert_eq(recovered.controls.length(), 7)
  for index, kind in kinds {
    assert_eq(recovered.controls[index].kind, kind)
    assert_eq(recovered.controls[index].at.to_a1(), "D\{index * 2 + 1}")
  }
}

///|
test "what a control writes and steps through comes back" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_control({
    ..bare_control(SpinButton, "D2"),
    link: Some(at("F2")),
    min: Some(1),
    max: Some(5),
    step: Some(2),
    value: Some(3),
    horizontal: Some(true),
  })
  sheet.add_control({
    ..bare_control(CheckBox, "D6"),
    text: Some("Rush order"),
    checked: Some(true),
    link: Some(at("F6")),
  })
  let recovered = only_sheet(wb)
  let spin = recovered.controls[0]
  assert_eq(spin.link.map(cell => cell.to_a1()), Some("F2"))
  assert_eq(spin.min, Some(1))
  assert_eq(spin.max, Some(5))
  assert_eq(spin.step, Some(2))
  assert_eq(spin.value, Some(3))
  assert_eq(spin.horizontal, Some(true))
  let box = recovered.controls[1]
  assert_eq(box.text, Some("Rush order"))
  assert_eq(box.checked, Some(true))
  assert_eq(box.link.map(cell => cell.to_a1()), Some("F6"))
}

///|
test "a control's size does not survive, and says so" {
  // The size is in the VML anchor's far corner, and the parser reads the
  // anchor's first two coordinates only. If this ever starts passing the size
  // back, this test fails and the note it pins becomes a lie worth deleting.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_control({
    ..bare_control(CheckBox, "D2"),
    width: Some(110),
    height: Some(20),
  })
  let recovered = round_trip(wb)
  let control = recovered.workbook.sheets[0].controls[0]
  assert_eq(control.width, None)
  assert_eq(control.height, None)
  assert_true(noted(recovered, "any size on a form control"))
}

///|
test "a control field the schema forbids on that kind is dropped" {
  // The loader refuses `checked` on a button and `page` on a spin button, so a
  // file that holds them must not become a spec that carries them: it would not
  // compile. Nothing but a hand-built model can put them there, which is why
  // this goes through the model rather than through a spec.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_control({
    ..bare_control(Button, "D2"),
    checked: Some(true),
    link: Some(at("F2")),
    min: Some(1),
  })
  sheet.add_control({ ..bare_control(SpinButton, "D6"), page: Some(4), })
  let recovered = round_trip(wb)
  let button = recovered.workbook.sheets[0].controls[0]
  assert_eq(button.checked, None)
  assert_eq(button.link, None)
  assert_eq(button.min, None)
  assert_eq(recovered.workbook.sheets[0].controls[1].page, None)
  assert_true(noted(recovered, "only on the kinds whose dialog offers it"))
}

///|
test "a control range that runs backwards loses both bounds" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_control({
    ..bare_control(ScrollBar, "D2"),
    min: Some(9),
    max: Some(2),
  })
  let recovered = round_trip(wb)
  let control = recovered.workbook.sheets[0].controls[0]
  assert_eq(control.min, None)
  assert_eq(control.max, None)
  assert_true(noted(recovered, "runs backwards"))
}

///|
/// A sheet with a table a slicer can filter.
fn with_table(wb : @model.Workbook) -> @model.Sheet {
  let sheet = wb.add_sheet("S")
  sheet.set(at("A1"), Text("Region"))
  sheet.set(at("B1"), Text("Revenue"))
  for row in 2..<=5 {
    sheet.set(at("A\{row}"), Text("R\{row}"))
    sheet.set(at("B\{row}"), Number(row.to_double()))
  }
  sheet.add_table({
    at: @model.CellRange::parse("A1:B5").unwrap(),
    name: Some("Sales"),
    style: None,
    banded_rows: true,
    banded_columns: false,
    first_column: false,
    last_column: false,
  })
  sheet
}

///|
test "a slicer comes back naming the same table column" {
  let wb = @model.Workbook::new()
  let sheet = with_table(wb)
  sheet.add_slicer({
    at: at("D2"),
    table: "Sales",
    column: "Region",
    caption: Some("Pick a region"),
    width: Some(180),
    height: Some(150),
    header: Some(false),
  })
  let recovered = only_sheet(wb)
  assert_eq(recovered.slicers.length(), 1)
  let slicer = recovered.slicers[0]
  assert_eq(slicer.at.to_a1(), "D2")
  assert_eq(slicer.table, "Sales")
  assert_eq(slicer.column, "Region")
  assert_eq(slicer.caption, Some("Pick a region"))
  assert_eq(slicer.width, Some(180))
  assert_eq(slicer.height, Some(150))
  assert_eq(slicer.header, Some(false))
}

///|
test "a slicer at the backend's own size says nothing about it" {
  let wb = @model.Workbook::new()
  let sheet = with_table(wb)
  sheet.add_slicer({
    at: at("D2"),
    table: "Sales",
    column: "Region",
    caption: None,
    width: None,
    height: None,
    header: None,
  })
  let slicer = only_sheet(wb).slicers[0]
  assert_eq(slicer.width, None)
  assert_eq(slicer.height, None)
  assert_eq(slicer.caption, None)
  assert_eq(slicer.header, None)
}

///|
test "a slicer's own defined name is not recovered as a definition" {
  // The backend writes `Slicer_Region` as a workbook-wide defined name when it
  // places the slicer. Recovering it *and* the slicer would make the spec
  // declare the name and then place something that declares it again, which the
  // backend refuses with DefinedNameDuplicate — so the spec would not compile.
  let wb = @model.Workbook::new()
  let sheet = with_table(wb)
  sheet.add_slicer({
    at: at("D2"),
    table: "Sales",
    column: "Region",
    caption: None,
    width: None,
    height: None,
    header: None,
  })
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.defined_names, [])
  let _ = @emit.to_bytes(recovered.workbook)
}

///|
/// A shape with nothing set but its position and geometry.
fn bare_shape(preset : String, at_ref : String) -> @model.Shape {
  {
    at: at(at_ref),
    preset,
    text: None,
    width: None,
    height: None,
    fill: None,
    line_color: None,
    line_width: None,
    alt_text: None,
    positioning: Move,
  }
}

///|
test "a shape comes back with its geometry, size, colours, and anchor" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_shape({
    ..bare_shape("cloud", "D2"),
    width: Some(220),
    height: Some(110),
    fill: @units.Color::parse("D6E9F8"),
    line_color: @units.Color::parse("1F77B4"),
    line_width: Some(2.0),
    alt_text: Some("An approval stamp"),
    positioning: Fixed,
  })
  let recovered = only_sheet(wb)
  assert_eq(recovered.shapes.length(), 1)
  let shape = recovered.shapes[0]
  assert_eq(shape.at.to_a1(), "D2")
  assert_eq(shape.preset, "cloud")
  assert_eq(shape.width, Some(220))
  assert_eq(shape.height, Some(110))
  assert_eq(shape.fill.map(color => color.hex()), Some("D6E9F8"))
  assert_eq(shape.line_color.map(color => color.hex()), Some("1F77B4"))
  assert_eq(shape.line_width, Some(2.0))
  assert_eq(shape.alt_text, Some("An approval stamp"))
  assert_true(shape.positioning is Fixed)
}

///|
test "a shape at the backend's own size and outline says nothing about them" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_shape(bare_shape("ellipse", "D2"))
  let shape = only_sheet(wb).shapes[0]
  assert_eq(shape.width, None)
  assert_eq(shape.height, None)
  assert_eq(shape.line_width, None)
  assert_eq(shape.line_color, None)
  assert_eq(shape.fill, None)
}

///|
test "a shape geometry spelled with a capital cannot come back" {
  // The backend lowercases the `prst` token on the way out, so `roundRect`
  // reads back as `roundrect`, which names no geometry the schema knows and
  // could not be told from any other. The schema refuses those geometries on
  // the way in for the same reason; this is the other end of it.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_shape(bare_shape("roundRect", "D2"))
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets[0].shapes, [])
  assert_true(noted(recovered, "roundrect"))
}

///|
test "shape text comes back, and the font on it does not" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_shape({
    ..bare_shape("chevron", "D2"),
    text: Some(
      Lines([
        {
          text: "Next",
          font: Some({
            name: None,
            size: None,
            bold: Some(true),
            italic: None,
            underline: None,
            strike: None,
            color: None,
          }),
        },
        { text: "quarter", font: None, },
      ]),
    ),
  })
  sheet.add_shape({ ..bare_shape("plus", "D8"), text: Some(Plain("Approved")), })
  let recovered = round_trip(wb)
  let shapes = recovered.workbook.sheets[0].shapes
  assert_eq(
    shapes[0].text,
    Some(
      Lines([{ text: "Next", font: None, }, { text: "quarter", font: None, }]),
    ),
  )
  assert_eq(shapes[1].text, Some(Plain("Approved")))
  assert_true(noted(recovered, "any font on a line of shape text"))
}

///|
/// A sparkline group over `B1:B3` with everything at its default.
fn bare_group(
  kind : @model.SparklineKind,
  at_ref : String,
) -> @model.SparklineGroup {
  {
    kind,
    cells: [
      {
        at: at(at_ref),
        data: { sheet: None, range: @model.CellRange::parse("B1:B3").unwrap(), },
      },
    ],
    markers: false,
    high: false,
    low: false,
    min: None,
    max: None,
    weight: None,
    color: None,
    markers_color: None,
    high_color: None,
    low_color: None,
    axis: false,
  }
}

///|
/// A sheet with three numbers for a sparkline to plot.
fn with_series(wb : @model.Workbook, name : String) -> @model.Sheet {
  let sheet = wb.add_sheet(name)
  for row in 1..<=3 {
    sheet.set(at("B\{row}"), Number(row.to_double()))
  }
  sheet
}

///|
test "a sparkline group comes back with its kind, points, and bounds" {
  let wb = @model.Workbook::new()
  let sheet = with_series(wb, "S")
  sheet.add_sparkline_group({
    ..bare_group(Line, "C1"),
    cells: [
      {
        at: at("C1"),
        data: { sheet: None, range: @model.CellRange::parse("B1:B3").unwrap(), },
      },
      {
        at: at("C2"),
        data: { sheet: None, range: @model.CellRange::parse("B1:B3").unwrap(), },
      },
    ],
    markers: true,
    high: true,
    low: true,
    min: Some(0),
    max: Some(10),
    weight: Some(2.25),
    axis: true,
  })
  let recovered = only_sheet(wb)
  assert_eq(recovered.sparklines.length(), 1)
  let group = recovered.sparklines[0]
  assert_true(group.kind is Line)
  assert_eq(group.cells.length(), 2)
  assert_eq(group.cells[0].at.to_a1(), "C1")
  assert_eq(group.cells[0].data.range.to_a1(), "B1:B3")
  assert_eq(group.markers, true)
  assert_eq(group.high, true)
  assert_eq(group.low, true)
  assert_eq(group.min, Some(0))
  assert_eq(group.max, Some(10))
  assert_eq(group.weight, Some(2.25))
  assert_eq(group.axis, true)
}

///|
test "a sparkline colour comes back only where the file names one" {
  let wb = @model.Workbook::new()
  let sheet = with_series(wb, "S")
  sheet.add_sparkline_group({
    ..bare_group(Line, "C1"),
    color: @units.Color::parse("1F77B4"),
    high_color: @units.Color::parse("CC0000"),
  })
  sheet.add_sparkline_group(bare_group(Column, "D1"))
  let recovered = only_sheet(wb)
  // The file writes an ARGB and the alpha here is `FF`, which says nothing a
  // spec needs to carry, so the colour comes back spelled the way it went in.
  assert_eq(recovered.sparklines[0].color.map(c => c.hex()), Some("1F77B4"))
  assert_eq(
    recovered.sparklines[0].high_color.map(c => c.hex()),
    Some("CC0000"),
  )
  // A group that named no colour gets the theme's, which is not a colour the
  // spec can write down — and saying it would put four on every group.
  assert_eq(recovered.sparklines[1].color, None)
  assert_eq(recovered.sparklines[1].high_color, None)
  assert_eq(recovered.sparklines[1].markers_color, None)
}

///|
test "markers on a sparkline that is not a line are dropped" {
  // Only a line sparkline draws them, and the schema follows Excel's dialog in
  // refusing them elsewhere — so carrying one through would make a spec that
  // does not load.
  let wb = @model.Workbook::new()
  let sheet = with_series(wb, "S")
  sheet.add_sparkline_group({
    ..bare_group(Column, "C1"),
    markers: true,
    weight: Some(3.0),
  })
  let recovered = round_trip(wb)
  let group = recovered.workbook.sheets[0].sparklines[0]
  assert_eq(group.markers, false)
  assert_eq(group.weight, None)
  assert_true(noted(recovered, "not a line"))
}

///|
test "the sheet a sparkline plots from is lost, and only said where it can be" {
  // The backend's reader keeps only what follows the `!`, so a group that
  // plotted `Data!B1:B3` comes back plotting this sheet's `B1:B3` — the same
  // shape of answer, the wrong numbers. Nothing at the seam can tell the two
  // apart, which is why this is reported rather than worked around.
  let wb = @model.Workbook::new()
  let _ = with_series(wb, "Data")
  let sheet = wb.add_sheet("S")
  sheet.set(at("A1"), Text("x"))
  sheet.add_sparkline_group({
    ..bare_group(Line, "C1"),
    cells: [
      {
        at: at("C1"),
        data: {
          sheet: Some("Data"),
          range: @model.CellRange::parse("B1:B3").unwrap(),
        },
      },
    ],
  })
  let recovered = round_trip(wb)
  let group = recovered.workbook.sheets[1].sparklines[0]
  assert_eq(group.cells[0].data.sheet, None)
  assert_true(noted(recovered, "comes back plotting this one"))
}

///|
test "a one-sheet workbook says nothing about a sparkline's sheet" {
  // With one sheet a qualifier could only ever have named that sheet, so
  // nothing can have been lost and the note would be pure noise.
  let wb = @model.Workbook::new()
  let sheet = with_series(wb, "S")
  sheet.add_sparkline_group(bare_group(Line, "C1"))
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets[0].sparklines.length(), 1)
  assert_true(!noted(recovered, "comes back plotting this one"))
}
