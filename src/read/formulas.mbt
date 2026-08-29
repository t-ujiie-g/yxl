///|
/// The shared-formula masters whose whole range comes back as one `formulas:`
/// entry, as the set of cell addresses those ranges cover.
///
/// The fold is refused where a cell in the range wears a style, because a
/// `formulas:` range carries no styling (docs/spec.md §3) and there would be
/// nowhere to put it — those ranges come back as ordinary cells instead, each
/// with its own translated formula, which loses the sharing but nothing else.
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
      sheet.add_formula({ at: range, formula: info.formula, })
      for r in range.top_left.row..<=range.bottom_right.row {
        for c in range.top_left.col..<=range.bottom_right.col {
          covered.add(@units.CellRef::new(col=c, row=r).to_a1())
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
  index : UInt,
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
      let reference = @units.CellRef::new(col~, row~).to_a1()
      if read_cell_style(backend, sheet_name, reference, styles, notes)
        is Some(_) {
        return false
      }
    }
  }
  true
}

///|
/// The formula a shared-formula follower stands for, translated from its master
/// to this cell's position, or `None` where the cell follows nothing.
///
/// The translation is the backend's own — the same shifting Excel applies when
/// it opens the file — so `D3` under a master `B2*C2` at `D2` comes back as
/// `B3*C3`, and an absolute `$C$2` does not move.
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
