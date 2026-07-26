// Emitting pivot tables. Both ranges go to the backend sheet-qualified, the way
// Excel stores them; the cache is left without records, so Excel builds the
// summary from the source the moment the workbook opens.

///|
/// Place a pivot table on a sheet.
///
/// The backend takes each field's *name* and looks it up in the source's header
/// row, so the cells must already be written — `emit_sheet` runs this after
/// them, and the loader has already checked that every field is a column there.
fn apply_pivot(
  backend : @xlsx.Workbook,
  sheet_name : String,
  pivot : @model.Pivot,
) -> Unit raise {
  let options = @xlsx.PivotTableOptions::new(
    sheet_range(pivot.source.sheet.unwrap_or(sheet_name), pivot.source.range),
    sheet_range(sheet_name, pivot.at),
  )
  for field in pivot.rows {
    options.rows.push(grouping_field(field))
  }
  for field in pivot.columns {
    options.columns.push(grouping_field(field))
  }
  for value in pivot.values {
    options.data.push(
      @xlsx.PivotTableField::new(
        value.field,
        name=value.name.unwrap_or(""),
        subtotal=pivot_function(value.function),
      ),
    )
  }
  if pivot.name is Some(name) {
    options.name = name
  }
  if pivot.style is Some(style) {
    options.pivot_table_style_name = style
  }
  options.row_grand_totals = pivot.row_grand_totals
  options.col_grand_totals = pivot.column_grand_totals
  backend.add_pivot_table(options) |> ignore
}

///|
/// A range as the backend's pivot options want one: `Orders!A1:D7`, with the
/// sheet name bare. Unlike a chart's, this string is *split* on its `!` and the
/// halves written into the pivot's XML as they are, so quoting the name — the
/// way Excel itself would — would name a sheet that does not exist. The loader
/// keeps a `!` out of a sheet name a pivot mentions, since nothing here could
/// tell one apart from the separator.
fn sheet_range(sheet_name : String, range : @model.CellRange) -> String {
  sheet_name + "!" + plain_range(range)
}

///|
/// A field on a grouping axis. Only a row, column, or filter field carries a
/// display name here; how it aggregates is a value field's business.
fn grouping_field(field : @model.PivotField) -> @xlsx.PivotTableField raise {
  @xlsx.PivotTableField::new(field.field, name=field.name.unwrap_or(""))
}

///|
/// The OOXML name of an aggregation (ECMA-376 §18.18.17,
/// `ST_DataConsolidateFunction`).
fn pivot_function(function : @model.PivotFunction) -> String {
  match function {
    Sum => "sum"
    Count => "count"
    CountNumbers => "countNums"
    Average => "average"
    Max => "max"
    Min => "min"
    Product => "product"
    StdDev => "stdDev"
    StdDevP => "stdDevp"
    Var => "var"
    VarP => "varp"
  }
}
