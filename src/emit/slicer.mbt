// Emitting slicers. The backend writes the several linked parts — the slicer,
// its cache, the defined name that anchors it — from one options bundle; the
// loader has already proven the table and column exist.

///|
/// Place a slicer. The backend wants the sheet the table sits on; the loader
/// proved the name resolves, so the scan here cannot miss.
fn apply_slicer(
  backend : @xlsx.Workbook,
  sheet_name : String,
  slicer : @model.Slicer,
  wb : @model.Workbook,
) -> Unit raise {
  let mut table_sheet = sheet_name
  for sheet in wb.sheets {
    for table in sheet.tables {
      if table.name is Some(name) && name.to_lower() == slicer.table.to_lower() {
        table_sheet = sheet.name
      }
    }
  }
  let options = @xlsx.SlicerOptions::new(
    slicer.column,
    slicer.at.to_a1(),
    table_sheet,
    slicer.table,
  )
  if slicer.caption is Some(caption) {
    options.set_caption(caption)
  }
  if slicer.width is Some(width) && slicer.height is Some(height) {
    options.set_size(width, height)
  }
  if slicer.header is Some(header) {
    options.set_display_header(Some(header))
  }
  backend.add_slicer(sheet_name, options)
}
