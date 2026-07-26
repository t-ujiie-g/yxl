// Emitting Excel tables (ListObjects). A table names a region and how it looks;
// the cells inside it are written as ordinary cells before this runs.

///|
/// Declare a range an Excel table.
///
/// The backend reads the column names out of the range's top row, so the sheet's
/// cells must already be written — `emit_sheet` calls this after them. The
/// loader has already checked that every header cell holds text, so the backend
/// never reaches its fallback of inventing `Column1`, `Column2`, … and writing
/// them into the sheet.
fn apply_table(
  backend : @xlsx.Workbook,
  sheet_name : String,
  table : @model.Table,
) -> Unit raise {
  let options = @xlsx.TableOptions::new(plain_range(table.at))
  if table.name is Some(name) {
    options.set_name(name)
  }
  if table.style is Some(style) {
    options.set_style_name(style)
  }
  options.set_show_row_stripes(Some(table.banded_rows))
  options.set_show_column_stripes(table.banded_columns)
  options.set_show_first_column(table.first_column)
  options.set_show_last_column(table.last_column)
  backend.add_table(sheet_name, options) |> ignore
}
