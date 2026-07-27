// Emitting a filled formula range as Excel's own shared formula.

///|
/// Write one formula across a region.
///
/// This compiles to a **shared formula** (ECMA-376 §18.3.1.40): the master cell
/// at the top-left stores the formula text once with the range it governs, and
/// every other cell in the range records only that it follows the master.
/// Excel shifts the relative references for each follower when it opens the
/// file, so the translation is never computed here and never stored — one spec
/// line becomes one stored formula, which is what ADR-004 asks of any reuse the
/// spec declares once.
///
/// The backend requires the master to be the range's top-left cell, which
/// `CellRange` guarantees by construction.
///
/// The cells the range fills are then styled from the sheet's bands. They have
/// to be done here rather than with the rest: the backend creates them, so they
/// are in no `cells` array for `emit_sheet` to walk, and a cell that exists with
/// no style of its own is style 0 rather than the column's (ECMA-376
/// §18.3.1.13). Without this a formula column could not be formatted at all,
/// since `formulas:` carries no styling itself and a band is where it belongs.
fn apply_formula_range(
  backend : @xlsx.Workbook,
  sheet_name : String,
  sheet : @model.Sheet,
  range : @model.FormulaRange,
  style_ids : Map[@model.Style, Int],
) -> Unit raise {
  backend.set_cell_formula_opts(
    sheet_name,
    range.at.top_left.to_a1(),
    range.formula,
    opts=@xlsx.FormulaOpts::shared(range.at.to_a1()),
  )
  // Nothing to lay down when the sheet declares no bands at all — worth the
  // check, because a range may legitimately cover a whole column.
  guard !(sheet.columns.is_empty() && sheet.rows.is_empty()) else { return }
  for row in range.at.top_left.row..<=range.at.bottom_right.row {
    for col in range.at.top_left.col..<=range.at.bottom_right.col {
      let at = @units.CellRef::new(col~, row~)
      // The text-cell exemption that `effective_style` applies does not arise:
      // a formula's result has no type until Excel computes it, and the cell is
      // written as a numeric one, so an inherited number format is exactly what
      // a calculation column wants.
      if band_style_at(sheet, at) is Some(style) {
        backend.set_cell_style(
          sheet_name,
          at.to_a1(),
          intern_style(backend, style_ids, style),
        )
      }
    }
  }
}
