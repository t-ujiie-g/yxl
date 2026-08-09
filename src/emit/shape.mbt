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
      // A shape is DrawingML, where a colour is three bytes and the backend
      // writes this string through verbatim; an alpha byte reaches the file as
      // `<a:srgbClr val="FF1F77B4"/>`, which is one byte too many.
      fill_color?=shape.fill.map(color => color.rgb()),
      line_color?=shape.line_color.map(color => color.rgb()),
      line_width?=shape.line_width,
      alt_text?=shape.alt_text,
      positioning=positioning(shape.positioning),
    ),
  )
}
