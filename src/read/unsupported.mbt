///|
/// Note what this sheet holds that the reader will not bring back.
///
/// Presence is read off the worksheet's own fields rather than through the
/// accessors that merge in defaults — `page_layout_with_defaults` aliases a
/// module-level default instead of copying it, so asking it whether a sheet has
/// print setup would make one sheet's answer leak into every later sheet's.
fn read_unsupported(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit {
  guard backend.sheet(sheet.name) is Some(source) else { return }
  // Charts are not here: `chart.mbt` reads the part itself and reports each one
  // it cannot follow, with the reason. A blanket note would say less and would
  // fire on the charts that did come back.
  if !source.pivot_tables.is_empty() {
    notes.drop(
      "a pivot table, which the Excel backend hands back as raw XML rather than as the fields the spec names",
    )
  }
  if has_print_setup(source) {
    notes.drop(
      "a sheet's print setup — its area, orientation, scaling, margins, header and footer, and page breaks — which the Excel backend cannot report per sheet without one sheet's answer leaking into the next",
    )
  }
}

///|
/// Whether the sheet says anything about how it prints.
fn has_print_setup(source : @xlsx.Worksheet) -> Bool {
  source.page_layout is Some(_) ||
  source.page_margins is Some(_) ||
  source.header_footer is Some(_) ||
  !source.row_breaks.is_empty() ||
  !source.col_breaks.is_empty()
}
