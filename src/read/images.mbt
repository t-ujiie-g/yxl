// Recovering the pictures on a sheet, and the one tiled behind it.
//
// These are the only things the reader hands back that are not text: the bytes
// come out whole and stay in the model, exactly as they do on the way in
// (ADR-003 — the core still opens nothing itself). Writing them out is the
// caller's job, as the CSV tables are.

///|
/// The pictures anchored on a sheet, and the sheet's background if it has one.
fn read_images(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit raise {
  // The backend lists the anchor cells and answers per cell, so the two calls
  // together are what an `images:` block holds.
  for reference in backend.get_picture_cells(sheet.name) {
    guard @units.CellRef::parse_a1(reference) is Some(at) else { continue }
    for picture in backend.get_pictures(sheet.name, reference) {
      if read_image(at, picture, notes) is Some(image) {
        sheet.add_image(image)
      }
    }
  }
  if backend.sheet(sheet.name) is Some(source) &&
    source.sheet_background() is Some(background) {
    if image_format(background.extension, notes) is Some(format) {
      sheet.set_background({ data: background.data, format })
    }
  }
}

///|
/// One picture, or `None` where its format is one the schema has no name for.
fn read_image(
  at : @units.CellRef,
  picture : @xlsx.Image,
  notes : Notes,
) -> @model.Image? {
  guard image_format(picture.extension, notes) is Some(format) else {
    return None
  }
  if !picture.hyperlink.is_empty() {
    // A picture may carry a link of its own; a spec puts links on cells.
    notes.drop("a hyperlink on a picture, which the spec sets on cells only")
  }
  if !picture.print_object {
    notes.drop("a picture marked not to print, which the spec cannot say")
  }
  // The scale is baked into an absolute size when the file is written, and the
  // backend reports it back as 1 whatever it was — so a scaled picture cannot
  // be told from an unscaled one, and every picture comes back at its natural
  // size. Recovering the factor would mean reading the image's own header for
  // its pixel dimensions, per format; until then this is said rather than
  // silently applied, because a picture quietly twice its intended size is
  // exactly the kind of change nobody looks for.
  notes.drop(
    "a picture's display size, which the file records as absolute dimensions rather than a scale — pictures come back at their natural size",
  )
  Some({
    at,
    data: picture.data,
    format,
    alt_text: if picture.alt_text.is_empty() {
      None
    } else {
      Some(picture.alt_text)
    },
    scale_x: picture.scale_x,
    scale_y: picture.scale_y,
    offset_x: picture.offset_x,
    offset_y: picture.offset_y,
    positioning: match picture.positioning {
      OneCell => Move
      TwoCell => MoveAndSize
      Absolute => Fixed
    },
  })
}

///|
/// An extension as the schema spells a format: lower case, no dot, and one Excel
/// actually stores.
fn image_format(extension : String, notes : Notes) -> String? {
  let bare = if extension.has_prefix(".") {
    extension[1:].to_owned()
  } else {
    extension
  }
  let format = bare.to_lower()
  guard @model.image_formats.contains(format) else {
    notes.drop(
      "a picture stored as '\{extension}', which the spec has no format name for",
    )
    return None
  }
  Some(format)
}
