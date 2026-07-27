// Emitting sparklines. The backend writes them as the `x14` worksheet
// extension Excel expects (ECMA-376 Part 4 §2.9); what crosses the seam here
// is one options bundle per group.

///|
/// Place one sparkline group on a sheet.
fn apply_sparkline_group(
  backend : @xlsx.Workbook,
  sheet_name : String,
  group : @model.SparklineGroup,
) -> Unit raise {
  let locations = group.cells.map(cell => cell.at.to_a1())
  let ranges = group.cells.map(cell => {
    match cell.data.sheet {
      // A range naming its sheet passes through the backend untouched, so it is
      // quoted here the way Excel writes it; a bare range is qualified by the
      // backend with the host sheet.
      Some(sheet) => quoted_sheet(sheet) + "!" + cell.data.range.to_a1()
      None => cell.data.range.to_a1()
    }
  })
  let options = @xlsx.SparklineOptions::new(locations[:], ranges[:])
  options.set_type(
    match group.kind {
      Line => Line
      Column => Column
      WinLoss => WinLoss
    },
  )
  if group.markers {
    options.set_markers(true)
  }
  if group.high {
    options.set_high(true)
  }
  if group.low {
    options.set_low(true)
  }
  if group.min is Some(min) {
    options.set_manual_min(min)
  }
  if group.max is Some(max) {
    options.set_manual_max(max)
  }
  if group.weight is Some(weight) {
    options.set_weight(weight)
  }
  if group.color is Some(color) {
    options.set_series_color(color.hex())
  }
  if group.markers_color is Some(color) {
    options.set_markers_color(color.hex())
  }
  if group.high_color is Some(color) {
    options.set_high_color(color.hex())
  }
  if group.low_color is Some(color) {
    options.set_low_color(color.hex())
  }
  if group.axis {
    options.set_axis(true)
  }
  backend.add_sparkline(sheet_name, options)
}
