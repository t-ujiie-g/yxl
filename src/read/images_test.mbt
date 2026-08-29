///|
/// A minimal but real PNG, so the backend stores and returns actual bytes.
fn png() -> Bytes {
  b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
}

///|
/// A workbook with one picture at `E1`, plus whatever `adjust` changes.
fn with_image(image : @model.Image) -> @model.Sheet raise {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_image(image)
  only_sheet(wb)
}

///|
/// A picture at `E1` with everything at its default.
fn plain_image() -> @model.Image {
  {
    at: at("E1"),
    data: png(),
    format: "png",
    alt_text: None,
    scale_x: 1.0,
    scale_y: 1.0,
    offset_x: 0,
    offset_y: 0,
    positioning: Move,
  }
}

///|
test "a picture comes back where it was, with its bytes unchanged" {
  let recovered = with_image(plain_image())
  assert_eq(recovered.images.length(), 1)
  assert_eq(recovered.images[0].at.to_a1(), "E1")
  assert_eq(recovered.images[0].format, "png")
  assert_eq(recovered.images[0].data, png())
}

///|
test "a picture's alt text, offset, and positioning come back" {
  let recovered = with_image({
    ..plain_image(),
    alt_text: Some("Example Ltd logo"),
    offset_x: 4,
    offset_y: 6,
    positioning: MoveAndSize,
  })
  let image = recovered.images[0]
  assert_eq(image.alt_text, Some("Example Ltd logo"))
  assert_eq(image.offset_x, 4)
  assert_eq(image.offset_y, 6)
  assert_true(image.positioning is MoveAndSize)
}

///|
test "each positioning comes back as itself" {
  for positioning in [@model.Move, MoveAndSize, Fixed] {
    let recovered = with_image({ ..plain_image(), positioning, })
    assert_eq(
      (positioning, recovered.images[0].positioning),
      (positioning, positioning),
    )
  }
}

///|
test "a picture's scale is reported lost rather than silently applied" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_image({ ..plain_image(), scale_x: 0.5, scale_y: 0.5, })
  let recovered = round_trip(wb)
  // The backend bakes the scale into an absolute size and reports 1 back, so a
  // scaled picture cannot be told from an unscaled one.
  assert_eq(recovered.workbook.sheets[0].images[0].scale_x, 1.0)
  assert_true(
    recovered.dropped.iter().any(note => note.contains("natural size")),
  )
}

///|
test "a sheet background comes back, bytes and format" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_background({ data: png(), format: "png", })
  let recovered = only_sheet(wb)
  assert_true(recovered.background is Some(_))
  guard recovered.background is Some(background) else { return }
  assert_eq(background.format, "png")
  assert_eq(background.data, png())
}

///|
test "a sheet with no pictures says nothing about pictures" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  let recovered = round_trip(wb)
  assert_eq(recovered.workbook.sheets[0].images.length(), 0)
  assert_eq(recovered.workbook.sheets[0].background, None)
  assert_true(
    !recovered.dropped.iter().any(note => note.contains("natural size")),
  )
}
