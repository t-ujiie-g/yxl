///|
/// The cells covered by shared formulas that fold back into one `formulas:`
/// entry; a range with a styled cell does not, since a cell's style cannot be
/// told apart from its band's.
fn fold_shared_formulas(
  backend : @xlsx.Workbook,
  source : @xlsx.Worksheet,
  sheet : @model.Sheet,
  used : @model.CellRange,
  styles : StyleTable,
  notes : Notes,
) -> @set.Set[String] raise {
  let covered : @set.Set[String] = Set([])
  for row in used.top_left.row..<=used.bottom_right.row {
    for col in used.top_left.col..<=used.bottom_right.col {
      guard source.get_cell_formula_info_rc(row, col) is Some(info) else {
        continue
      }
      // A master is the cell that holds the text *and* names the range; a
      // follower holds the index alone.
      guard info.shared_index is Some(index) &&
        info.range_ref is Some(reference) &&
        !info.formula.is_empty() else {
        continue
      }
      guard @model.CellRange::parse(reference) is Some(range) else { continue }
      guard range_follows(
        source,
        backend,
        sheet.name,
        range,
        index,
        styles,
        notes,
      ) else {
        continue
      }
      sheet.add_formula({
        at: range,
        formula: @model.from_file_formula(info.formula),
        style: None,
      })
      for r in range.top_left.row..<=range.bottom_right.row {
        for c in range.top_left.col..<=range.bottom_right.col {
          covered.add(@units.CellRef(col=c, row=r).to_a1())
        }
      }
    }
  }
  covered
}

///|
/// Whether every cell of `range` follows the shared formula `index` and carries
/// no style of its own — the two things a `formulas:` range needs to be true of
/// the region it replaces.
fn range_follows(
  source : @xlsx.Worksheet,
  backend : @xlsx.Workbook,
  sheet_name : String,
  range : @model.CellRange,
  index : UInt32,
  styles : StyleTable,
  notes : Notes,
) -> Bool raise {
  for row in range.top_left.row..<=range.bottom_right.row {
    for col in range.top_left.col..<=range.bottom_right.col {
      guard source.get_cell_formula_info_rc(row, col) is Some(info) else {
        return false
      }
      guard info.shared_index is Some(other) && other == index else {
        return false
      }
      let reference = @units.CellRef(col~, row~).to_a1()
      if read_cell_style(backend, sheet_name, reference, styles, notes)
        is Some(_) {
        return false
      }
    }
  }
  true
}

///|
/// A shared-formula follower's formula, translated from its master by the
/// backend as Excel would, or `None`.
fn shared_follower_formula(
  source : @xlsx.Worksheet,
  at : @units.CellRef,
  notes : Notes,
) -> String? raise {
  guard source.get_cell_formula_info_rc(at.row, at.col) is Some(info) else {
    return None
  }
  guard info.formula.is_empty() && info.shared_index is Some(index) else {
    return None
  }
  guard source.shared_formula_master(index) is Some(master) else {
    notes.drop(
      "a cell following a shared formula whose master the file does not hold, which leaves nothing to translate",
    )
    return None
  }
  Some(master.translate_to(at.row, at.col))
}
