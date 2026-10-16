///|
/// Write one formula across a region as a shared formula (ECMA-376 §18.3.1.40),
/// then style its cells from the bands: the backend creates them, so `emit_sheet`
/// never sees them, and an unstyled cell is style 0 (§18.3.1.13).
fn apply_formula_range(
  backend : @xlsx.Workbook,
  sheet_name : String,
  sheet : @model.Sheet,
  range : @model.FormulaRange,
  style_ids : Map[@model.Style, Int32],
) -> Unit raise {
  backend.set_cell_formula_opts(
    sheet_name,
    range.at.top_left.to_a1(),
    @model.to_file_formula(range.formula),
    opts=@xlsx.FormulaOpts::shared(range.at.to_a1()),
  )
  // Nothing to lay down when neither a band nor the range styles a cell —
  // worth the check, because a range may legitimately cover a whole column.
  guard range.style is Some(_) ||
    !(sheet.columns.is_empty() && sheet.rows.is_empty()) else {
    return
  }
  for row in range.at.top_left.row..<=range.at.bottom_right.row {
    for col in range.at.top_left.col..<=range.at.bottom_right.col {
      let at = @units.CellRef(col~, row~)
      // The text-cell exemption that `effective_style` applies does not arise:
      // a formula's result has no type until Excel computes it, and the cell is
      // written as a numeric one, so an inherited number format is exactly what
      // a calculation column wants.
      if settle(@model.Style::layer(sheet.band_style_at(at), range.style))
        is Some(style) {
        backend.set_cell_style(
          sheet_name,
          at.to_a1(),
          intern_style(backend, style_ids, style),
        )
      }
    }
  }
}
