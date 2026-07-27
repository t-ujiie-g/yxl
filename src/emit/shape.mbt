// Emitting shapes. A shape crosses the seam as the backend's `Shape`, whose
// unset options keep the backend defaults — a 160-pixel square in the theme
// colours.

///|
/// Float a shape over a sheet.
fn apply_shape(
  backend : @xlsx.Workbook,
  sheet_name : String,
  shape : @model.Shape,
) -> Unit raise {
  let (text, paragraph) = match shape.text {
    Some(Plain(text)) => (Some(text), None)
    Some(Lines(lines)) => (None, Some(lines.map(build_rich_run)))
    None => (None, None)
  }
  backend.add_shape(
    sheet_name,
    @xlsx.Shape::new(
      shape.at.to_a1(),
      shape.preset,
      text?,
      paragraph?,
      width?=shape.width,
      height?=shape.height,
      fill_color?=shape.fill.map(color => color.hex()),
      line_color?=shape.line_color.map(color => color.hex()),
      line_width?=shape.line_width,
      alt_text?=shape.alt_text,
      positioning=positioning(shape.positioning),
    ),
  )
}
