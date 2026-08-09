///|
/// Stand-in file contents. Nothing here decodes an image, so any bytes will do.
let logo : Bytes = b"\x89PNG\r\n\x1a\n"

///|
/// A sheet with one image, and a `logo.png` for it to name.
fn image_spec(body : String) -> String {
  sheet_spec("    images:\n" + body)
}

///|
/// The sole image a spec loads.
fn loaded_image(body : String) -> @model.Image raise {
  let images = load_ok(image_spec(body), binaries={ "logo.png": logo }).sheets[0].images
  assert_eq(images.length(), 1)
  images[0]
}

///|
/// The diagnostic loading a spec produces, with `logo.png` available.
fn image_message(body : String) -> String? raise {
  schema_message(image_spec(body), binaries={ "logo.png": logo })
}

///|
test "an image loads its anchor, its bytes, and Excel's own placement" {
  let image = loaded_image("      - at: D2\n        file: logo.png\n")
  assert_eq(image.at.to_a1(), "D2")
  assert_eq(image.data, logo)
  assert_eq(image.format, "png")
  assert_eq(image.alt_text, None)
  assert_eq(image.scale_x, 1.0)
  assert_eq(image.scale_y, 1.0)
  assert_eq(image.offset_x, 0)
  assert_eq(image.offset_y, 0)
  assert_eq(image.positioning, Move)
}

///|
test "an image loads its alt text, scale, offset, and positioning" {
  let image = loaded_image(
    (
      #|      - at: D2
      #|        file: logo.png
      #|        alt: Company logo
      #|        scale: { x: 2, y: 0.5 }
      #|        offset: { x: 4, y: 6 }
      #|        positioning: move_and_size
      #|
    ),
  )
  assert_eq(image.alt_text, Some("Company logo"))
  assert_eq(image.scale_x, 2.0)
  assert_eq(image.scale_y, 0.5)
  assert_eq(image.offset_x, 4)
  assert_eq(image.offset_y, 6)
  assert_eq(image.positioning, MoveAndSize)
}

///|
test "one scale scales both directions" {
  let image = loaded_image(
    "      - at: D2\n        file: logo.png\n        scale: 0.25\n",
  )
  assert_eq(image.scale_x, 0.25)
  assert_eq(image.scale_y, 0.25)
}

///|
test "every positioning a spec may write is accepted" {
  for positioning in ["move", "move_and_size", "fixed"] {
    assert_eq(
      image_message(
        "      - at: D2\n        file: logo.png\n        positioning: \{positioning}\n",
      ),
      None,
    )
  }
}

///|
test "an unknown positioning is a diagnostic naming the three there are" {
  assert_eq(
    image_message(
      "      - at: D2\n        file: logo.png\n        positioning: floating\n",
    ),
    Some(
      "spec.yaml: unknown image positioning 'floating' in image at 'D2' (expected 'move', 'move_and_size', or 'fixed')",
    ),
  )
}

///|
test "the format comes from the file name, whatever its case" {
  let image = load_ok(
      image_spec("      - at: D2\n        file: art/Logo.PNG\n"),
      binaries={ "art/Logo.PNG": logo },
    ).sheets[0].images[0]
  assert_eq(image.format, "png")
}

///|
test "a format Excel cannot store is a diagnostic, not a broken workbook" {
  guard schema_message(
      image_spec("      - at: D2\n        file: logo.webp\n"),
      binaries={ "logo.webp": logo },
    )
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_true(
    message.has_prefix(
      "spec.yaml: image at 'D2' names 'logo.webp', whose format 'webp' Excel does not store",
    ),
  )
  assert_true(message.contains("png"))
}

///|
test "a file with no extension says so, rather than guessing a format" {
  assert_eq(
    schema_message(image_spec("      - at: D2\n        file: logo\n"), binaries={
      "logo": logo,
    }),
    Some(
      "spec.yaml: image at 'D2' names 'logo', which has no extension to say what format it is",
    ),
  )
}

///|
test "an empty file is a diagnostic rather than a picture of nothing" {
  assert_eq(
    schema_message(image_spec("      - at: D2\n        file: logo.png\n"), binaries={
      "logo.png": b"",
    }),
    Some("spec.yaml: image at 'D2' reads 'logo.png', which is empty"),
  )
}

///|
/// The bytes seam has a default that reads nothing, so a caller that cannot open
/// files gets a diagnostic instead of a silent failure.
test "a caller with no way to read files is told so" {
  let document = @yaml.parse(
    image_spec("      - at: D2\n        file: logo.png\n"),
    file="spec.yaml",
  )
  let message = try {
    @loader.load(document, file="spec.yaml") |> ignore
    None
  } catch {
    @diag.SchemaError(d) => Some(d.render())
    other => Some(other.to_string())
  }
  assert_eq(
    message,
    Some(
      "spec.yaml: cannot read 'logo.png' — this caller provides no way to read files",
    ),
  )
}

///|
test "an image needs an anchor and a file" {
  assert_eq(
    image_message("      - file: logo.png\n"),
    Some("spec.yaml: an image is missing required key 'at'"),
  )
  assert_eq(
    image_message("      - at: D2\n"),
    Some("spec.yaml: image at 'D2' is missing required key 'file'"),
  )
}

///|
test "an image, a scale, and an offset each reject an unknown key" {
  let cases = [
    (
      "      - at: D2\n        file: logo.png\n        rotate: 90\n", "unknown key 'rotate' in image at 'D2'",
    ),
    (
      "      - at: D2\n        file: logo.png\n        scale: { x: 2, z: 3 }\n",
      "unknown key 'z' in image at 'D2' 'scale'",
    ),
    (
      "      - at: D2\n        file: logo.png\n        offset: { x: 2, z: 3 }\n",
      "unknown key 'z' in image at 'D2' 'offset'",
    ),
  ]
  for entry in cases {
    let (body, expected) = entry
    guard image_message(body) is Some(message) else {
      fail("expected a diagnostic")
    }
    assert_true(message.has_prefix("spec.yaml: \{expected}"))
  }
}

///|
test "a scale must be positive, and an offset a whole number of pixels" {
  assert_eq(
    image_message("      - at: D2\n        file: logo.png\n        scale: 0\n"),
    Some(
      "spec.yaml: image at 'D2' 'scale' must be above 0 and at most 100, not 0",
    ),
  )
  assert_eq(
    image_message(
      "      - at: D2\n        file: logo.png\n        offset: { x: -1, y: 0 }\n",
    ),
    Some(
      "spec.yaml: image at 'D2' 'offset' 'x' must be between 0 and 20000 pixels, not -1",
    ),
  )
  assert_eq(
    image_message(
      "      - at: D2\n        file: logo.png\n        offset: { x: 1.5, y: 0 }\n",
    ),
    Some(
      "spec.yaml: image at 'D2' 'offset' 'x' must be a whole number of pixels",
    ),
  )
  assert_eq(
    image_message(
      "      - at: D2\n        file: logo.png\n        offset: { x: 4 }\n",
    ),
    Some("spec.yaml: image at 'D2' 'offset' needs both 'x' and 'y'"),
  )
}

///|
test "images keep their declaration order" {
  let wb = load_ok(
    image_spec(
      "      - at: D2\n        file: logo.png\n      - at: H10\n        file: logo.png\n",
    ),
    binaries={ "logo.png": logo },
  )
  let images = wb.sheets[0].images
  assert_eq(images.length(), 2)
  assert_eq(images[0].at.to_a1(), "D2")
  assert_eq(images[1].at.to_a1(), "H10")
}

///|
test "a background loads its bytes and format through the same seam" {
  let wb = load_ok(sheet_spec("    background: logo.png\n"), binaries={
    "logo.png": logo,
  })
  let background = wb.sheets[0].background.unwrap()
  assert_eq(background.data, logo)
  assert_eq(background.format, "png")
}

///|
test "a background refuses a formatless name, a foreign format, an empty file" {
  assert_eq(
    schema_message(sheet_spec("    background: logo\n"), binaries={
      "logo": logo,
    }),
    Some(
      "spec.yaml: sheet 'background' names 'logo', which has no extension to say what format it is",
    ),
  )
  assert_eq(
    schema_message(sheet_spec("    background: notes.txt\n"), binaries={
      "notes.txt": logo,
    }),
    Some(
      "spec.yaml: sheet 'background' names 'notes.txt', whose format 'txt' Excel does not store (expected bmp, emf, emz, gif, ico, jpeg, jpg, png, svg, tif, tiff, wmf, or wmz)",
    ),
  )
  assert_eq(
    schema_message(sheet_spec("    background: logo.png\n"), binaries={
      "logo.png": b"",
    }),
    Some("spec.yaml: sheet 'background' reads 'logo.png', which is empty"),
  )
  assert_eq(
    schema_message(sheet_spec("    background: 5\n")),
    Some("spec.yaml: sheet 'background' must be text"),
  )
}
