///|
/// Declare a range an Excel table. The backend reads column names from the top
/// row, so the cells must already be written.
fn apply_table(
  backend : @xlsx.Workbook,
  sheet_name : String,
  table : @model.Table,
) -> Unit raise {
  let options = @xlsx.TableOptions::new(table.at.to_a1())
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
