// Round-trip tests for shapes: compile the model to real bytes, re-open them
// with the backend reader, and assert on the shape the sheet carries.

///|
/// The sole shape the round-tripped workbook carries.
fn only_shape(wb : @model.Workbook) -> @xlsx.Shape raise {
  let reopened = reopen(wb)
  guard reopened.sheet("S") is Some(sheet) else { fail("missing sheet") }
  let shapes = sheet.shapes()
  assert_eq(shapes.length(), 1)
  shapes[0]
}

///|
test "a shape round-trips its geometry, anchor, colours, text, and alt text" {
  let (wb, sheet) = fixture()
  sheet.add_shape({
    at: @units.CellRef::new(col=3, row=3),
    preset: "cloud",
    text: Some(@model.Plain("Ship it")),
    width: Some(240),
    height: Some(120),
    fill: @units.Color::parse("1F77B4"),
    line_color: @units.Color::parse("333333"),
    line_width: Some(2.5),
    alt_text: Some("An approval stamp"),
    positioning: MoveAndSize,
  })
  let shape = only_shape(wb)
  assert_eq(shape.shape_type, "cloud")
  assert_eq(shape.cell, "C3")
  assert_eq(shape.fill_color, "1F77B4")
  assert_eq(shape.line_color, "333333")
  assert_true((shape.line_width - 2.5).abs() < 0.0001)
  assert_eq(shape.format.alt_text, Some("An approval stamp"))
  assert_true(shape.format.positioning is Some(TwoCell))
  assert_eq(shape.paragraph.length(), 1)
  assert_eq(shape.paragraph[0].text, "Ship it")
}

///|
test "a shape with defaults leaves the backend's own in place" {
  let (wb, sheet) = fixture()
  sheet.add_shape({
    at: @units.CellRef::new(col=2, row=2),
    preset: "rect",
    text: None,
    width: None,
    height: None,
    fill: None,
    line_color: None,
    line_width: None,
    alt_text: None,
    positioning: Move,
  })
  let shape = only_shape(wb)
  assert_eq(shape.shape_type, "rect")
  assert_eq(shape.cell, "B2")
  // An unset colour crosses the seam as the backend's "" (its own default).
  assert_eq(shape.fill_color, "")
  assert_eq(shape.line_color, "")
  assert_true(shape.format.positioning is Some(OneCell))
}

///|
test "a shape's text lines each round-trip as their own paragraph" {
  let (wb, sheet) = fixture()
  sheet.add_shape({
    at: @units.CellRef::new(col=2, row=2),
    preset: "chevron",
    text: Some(
      @model.Lines([
        { text: "next", font: None },
        {
          text: "quarter",
          font: Some({
            bold: Some(true),
            italic: None,
            underline: None,
            strike: None,
            size: None,
            name: None,
            color: None,
          }),
        },
      ]),
    ),
    width: None,
    height: None,
    fill: None,
    line_color: None,
    line_width: None,
    alt_text: None,
    positioning: Move,
  })
  let shape = only_shape(wb)
  // The backend's reader keeps each line's text but not its font (every run
  // comes back `font: None`), so the bold second line is asserted only as far
  // as the reader can see.
  assert_eq(shape.paragraph.length(), 2)
  assert_eq(shape.paragraph[0].text, "next")
  assert_eq(shape.paragraph[1].text, "quarter")
}
