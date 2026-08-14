///|
/// Lay one override over the cell the rest of the sheet has already written
/// (ADR-018).
///
/// A facet is written only when the override gives it, and the backend keeps
/// what it is not told to change — which is what makes the two independent: a
/// new value keeps the cell's style, a new style keeps its value.
///
/// A cell inside a `formulas:` range is a shared-formula follower until this
/// runs; writing a value or a formula over it drops it out of the group. The
/// loader has already refused an override of the group's anchor, where the
/// formula itself is stored.
fn apply_override(
  backend : @xlsx.Workbook,
  sheet_name : String,
  entry : @model.Override,
  style_ids : Map[@model.Style, Int],
  date_system : @units.DateSystem,
) -> Unit raise {
  match entry.value {
    Some(value) =>
      emit_cell(
        backend,
        sheet_name,
        { pos: entry.at, value, style: None },
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
