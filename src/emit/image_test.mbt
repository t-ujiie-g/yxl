// Round-trip tests for images: each compiles to real `.xlsx` bytes and is read
// back, so what is asserted is the picture Excel would find in the package.

///|
/// A 1×1 transparent PNG, the smallest file that is genuinely one. Written out
/// byte by byte so the test needs no fixture on disk: the signature, an `IHDR`
/// declaring 1×1 8-bit RGBA, one `IDAT`, and `IEND` (ISO/IEC 15948).
let tiny_png : Bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\x0aIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\x0d\x0a\x2d\xb4\x00\x00\x00\x00IEND\xaeB\x60\x82"

///|
/// An image at `D2`, placed the way Excel places a pasted one.
fn plain_image() -> @model.Image {
  {
    at: @units.CellRef::parse_a1("D2").unwrap(),
    data: tiny_png,
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
/// The sole image the round-tripped workbook carries.
///
/// The sheet's own `images()` is read rather than the workbook's
/// `get_pictures`: the latter also looks for images *inside* cells, a path that
/// drags Excel's formula evaluator into the link — and MSVC cannot parse the C
/// its thousand-armed dispatch generates (`fatal error C1026`). Drawing
/// pictures are what `yxl` emits, so this is the accessor that matches anyway.
fn only_image(wb : @model.Workbook) -> @xlsx.Image raise {
  let reopened = reopen(wb)
  guard reopened.sheet("S") is Some(sheet) else { fail("expected the sheet") }
  let images = sheet.images()
  assert_eq(images.length(), 1)
  images[0]
}

///|
test "an image round-trips as its own bytes at its own anchor" {
  let (wb, sheet) = fixture()
  sheet.add_image(plain_image())
  let image = only_image(wb)
  assert_eq(image.reference, "D2")
  // The bytes reach the package untouched — this is the one thing a spec
  // carries that is not text.
  assert_eq(image.data, tiny_png)
  assert_eq(image.extension, "png")
  assert_eq(image.content_type, "image/png")
}

///|
test "the placement a spec asks for reaches the file" {
  let (wb, sheet) = fixture()
  sheet.add_image({
    ..plain_image(),
    alt_text: Some("Company logo"),
    scale_x: 2.0,
    scale_y: 4.0,
    offset_x: 4,
    offset_y: 6,
  })
  let image = only_image(wb)
  assert_eq(image.alt_text, "Company logo")
  assert_eq(image.offset_x, 4)
  assert_eq(image.offset_y, 6)
  // A scale is not stored as a factor: Excel keeps the drawn size, which the
  // backend works out from the image's own — here 1×1 px — before writing it.
  // One pixel is 9525 EMU (ECMA-376 §20.1.2.1).
  assert_eq(image.width_emu, 2 * 9525)
  assert_eq(image.height_emu, 4 * 9525)
}

///|
/// The workbook a positioning produces, read back.
fn positioned(asked : @model.ImagePositioning) -> @xlsx.Image raise {
  let (wb, sheet) = fixture()
  sheet.add_image({ ..plain_image(), positioning: asked })
  only_image(wb)
}

///|
test "each positioning reaches the file as its own anchor kind" {
  // "Move but don't size", "move and size", and "don't move or size" — the
  // three anchors OOXML has (ECMA-376 §20.5.2.1).
  assert_true(positioned(Move).positioning is OneCell)
  assert_true(positioned(MoveAndSize).positioning is TwoCell)
  assert_true(positioned(Fixed).positioning is Absolute)
}

///|
test "two images on one sheet keep their own anchors" {
  let (wb, sheet) = fixture()
  sheet.add_image(plain_image())
  sheet.add_image({
    ..plain_image(),
    at: @units.CellRef::parse_a1("H10").unwrap(),
  })
  let reopened = reopen(wb)
  guard reopened.sheet("S") is Some(read) else { fail("expected the sheet") }
  assert_eq(read.images().map(image => image.reference), ["D2", "H10"])
}

///|
test "a background round-trips as the sheet's tiled image" {
  let (wb, sheet) = fixture()
  sheet.set_background({ data: tiny_png, format: "png" })
  let reopened = reopen(wb)
  guard reopened.sheet("S") is Some(reopened_sheet) else {
    fail("expected the sheet")
  }
  guard reopened_sheet.sheet_background() is Some(background) else {
    fail("expected a background")
  }
  assert_eq(background.extension, "png")
  assert_eq(background.content_type, "image/png")
  assert_eq(background.data, tiny_png)
}
