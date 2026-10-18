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
/// Tile a background image behind a sheet's cells. The extension crosses the
/// seam bare (`png`) — this backend call, unlike `add_picture_from_bytes`,
/// takes it with or without the dot.
fn apply_background(
  backend : @xlsx.Workbook,
  sheet_name : String,
  background : @model.SheetBackground,
) -> Unit raise {
  backend.set_sheet_background(sheet_name, background.data, background.format)
}

///|
/// The backend's anchor for a positioning (ECMA-376 §20.5.2.1): two-cell moves
/// and sizes with the cells, one-cell keeps the size, absolute stays put.
fn positioning(
  positioning : @model.ImagePositioning,
) -> @xlsx.PicturePositioning {
  match positioning {
    Move => OneCell
    MoveAndSize => TwoCell
    Fixed => Absolute
  }
}
