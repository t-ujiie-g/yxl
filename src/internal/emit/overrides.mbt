///|
/// Lay one override over its already-written cell (ADR-018), writing only the
/// facets it gives. Writing over a shared-formula follower drops it from the
/// group.
fn apply_override(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  entry : @model.Override,
  style_ids : Map[@model.Style, Int32],
  date_system : @units.DateSystem,
) -> Unit raise {
  let (written, own) = overridden_cell(sheet, entry.at)
  let value = entry.value.unwrap_or(written)
  // The override's look replaces the cell's own whole, as a later `cells:`
  // entry's does; the bands still lie under it (ADR-032). Re-drawn even for a
  // value alone: a new kind of value may change what the bands pass it.
  let style = drawn_style(
    sheet,
    entry.at,
    value,
    match entry.style {
      Some(_) => entry.style
      None => own
    },
  )
  if entry.value is Some(value) {
    emit_cell(
      backend,
      sheet.name,
      { pos: entry.at, value, style: None, },
      style_ids,
      date_system,
      style=None,
    )
  }
  backend.set_cell_style(
    sheet.name,
    entry.at.to_a1(),
    match style {
      Some(style) => intern_style(backend, style_ids, style)
      None => DEFAULT_STYLE_ID
    },
  )
}

///|
/// The `cellXfs` entry every workbook starts with (ECMA-376 §18.8.10).
const DEFAULT_STYLE_ID : Int32 = 0

///|
/// What the spec wrote at `at` before the override: the value and the cell's
/// own style, from its `cells:` entry or the `formulas:` range covering it.
fn overridden_cell(
  sheet : @model.Sheet,
  at : @units.CellRef,
) -> (@model.CellValue, @model.Style?) {
  if sheet.cells.iter().find_first(cell => cell.pos == at) is Some(cell) {
    return (cell.value, cell.style)
  }
  for range in sheet.formulas {
    if range.at.contains(at) {
      return (Formula(formula=range.formula, cached=None), range.style)
    }
  }
  (Blank, None)
}
