// Emitting images. The bytes were read while the spec loaded, so this writes
// them into the package and says where they go — no file is opened here
// (ADR-003).

///|
/// Anchor an image on a sheet.
fn apply_image(
  backend : @xlsx.Workbook,
  sheet_name : String,
  image : @model.Image,
) -> Unit raise {
  let options = @xlsx.GraphicOptions::with_values(
    offset_x=image.offset_x,
    offset_y=image.offset_y,
    scale_x=image.scale_x,
    scale_y=image.scale_y,
    alt_text=image.alt_text.unwrap_or(""),
    positioning=positioning(image.positioning),
  )
  backend.add_picture_from_bytes_with_options(
    sheet_name,
    image.at.to_a1(),
    image.data,
    // The backend spells a format as a file suffix, dot and all.
    "." + image.format,
    options,
  )
}

///|
/// The backend's anchor kind for a model positioning. OOXML has three anchors
/// (ECMA-376 §20.5.2.1): a two-cell one, whose second corner moves the drawing's
/// far edge with the cells; a one-cell one, which keeps the size; and an
/// absolute one, pinned to the sheet.
fn positioning(
  positioning : @model.ImagePositioning,
) -> @xlsx.PicturePositioning {
  match positioning {
    Move => OneCell
    MoveAndSize => TwoCell
    Fixed => Absolute
  }
}
