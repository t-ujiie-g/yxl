///|
/// Lay one override over its already-written cell (ADR-018), writing only the
/// facets it gives. Writing over a shared-formula follower drops it from the
/// group.
fn apply_override(
  backend : @xlsx.Workbook,
  sheet_name : String,
  entry : @model.Override,
  style_ids : Map[@model.Style, Int32],
  date_system : @units.DateSystem,
) -> Unit raise {
  match entry.value {
    Some(value) =>
      emit_cell(
        backend,
        sheet_name,
        { pos: entry.at, value, style: None, },
        style_ids,
        date_system,
        style=entry.style,
      )
    None =>
      if entry.style is Some(style) {
        backend.set_cell_style(
          sheet_name,
          entry.at.to_a1(),
          intern_style(backend, style_ids, style),
        )
      }
  }
}
