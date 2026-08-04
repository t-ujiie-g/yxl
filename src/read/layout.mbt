// Recovering how a sheet is laid out and how it prints: the column and row
// bands, the frozen panes, the tab, and the page setup.

///|
/// Column and row bands, one per column or row that differs from the default.
///
/// The backend answers per column rather than per band, so the run of columns
/// that share a look is rebuilt here — the file lost the fact that they were
/// declared together, and a band per column would turn one spec line into
/// hundreds.
fn read_bands(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  styles : StyleTable,
  notes : Notes,
) -> Unit raise {
  guard backend.sheet(sheet.name) is Some(source) else { return }
  // The `<col>` and `<row>` records themselves, rather than a scan of the used
  // range: a hidden column past the last cell is exactly the kind of thing a
  // scan would miss, and it is the kind of thing a spec has to keep.
  let column_records : Array[(Int, Track)] = []
  for index, dimension in source.col_dimensions {
    column_records.push(
      (
        index,
        (
          dimension.width,
          dimension.hidden,
          dimension.outline_level,
          read_band_style(backend, dimension.style_id, styles, notes),
        ),
      ),
    )
  }
  for band in tracks(column_records) {
    let (first, last, width, hidden, level, style) = band
    sheet.set_column_band(
      first~,
      last~,
      width?,
      hidden?,
      outline_level?=level,
      style?,
    )
  }
  let row_records : Array[(Int, Track)] = []
  for index, dimension in source.row_dimensions {
    row_records.push(
      (
        index,
        (
          dimension.height,
          dimension.hidden,
          dimension.outline_level,
          read_band_style(backend, dimension.style_id, styles, notes),
        ),
      ),
    )
  }
  for band in tracks(row_records) {
    let (first, last, height, hidden, level, style) = band
    sheet.set_row_band(
      first~,
      last~,
      height?,
      hidden?,
      outline_level?=level,
      style?,
    )
  }
}

///|
/// The style a column or row record carries, if any.
fn read_band_style(
  backend : @xlsx.Workbook,
  id : Int?,
  styles : StyleTable,
  notes : Notes,
) -> @model.Style? raise {
  match id {
    Some(id) => read_style_id(backend, id, styles, notes)
    None => None
  }
}

///|
/// What one column or row says about itself, before it is grouped into a band.
type Track = (Double?, Bool, Int, @model.Style?)

///|
/// A band as the model wants it: the span, then the four properties.
type Band = (Int, Int, Double?, Bool?, Int?, @model.Style?)

///|
/// Sort the records by index, drop the ones that say nothing, and collapse a run
/// of *adjacent* records that say the same thing into one band.
///
/// The collapsing is what keeps the result readable: a file records every column
/// separately, and the fact that twenty of them were declared together in one
/// line is exactly what compiling threw away.
fn tracks(records : Array[(Int, Track)]) -> Array[Band] {
  let ordered = records
  ordered.sort_by((left, right) => left.0 - right.0)
  let bands = []
  let mut start = 0
  while start < ordered.length() {
    let (index, track) = ordered[start]
    let (size, hidden, level, style) = track
    // A record at Excel's defaults contributes nothing; Excel writes them for
    // reasons of its own, and repeating them would bury the ones that matter.
    if size is None && !hidden && level == 0 && style is None {
      start += 1
      continue
    }
    let mut end = start
    while end + 1 < ordered.length() &&
          ordered[end + 1].1 == track &&
          ordered[end + 1].0 == ordered[end].0 + 1 {
      end += 1
    }
    bands.push(
      (
        index,
        ordered[end].0,
        size,
        if hidden {
          Some(true)
        } else {
          None
        },
        if level > 0 {
          Some(level)
        } else {
          None
        },
        style,
      ),
    )
    start = end + 1
  }
  bands
}

///|
/// Frozen or split panes, the on-screen grid, and the tab colour.
fn read_presentation(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit raise {
  let panes = backend.get_panes(sheet.name)
  if panes.freeze && (panes.x_split > 0 || panes.y_split > 0) {
    // A freeze is stored as the count of locked columns and rows; the schema
    // names the first cell that scrolls, which is one past each.
    sheet.set_panes(
      Freeze(@units.CellRef::new(col=panes.x_split + 1, row=panes.y_split + 1)),
    )
  } else if panes.split && (panes.x_split > 0 || panes.y_split > 0) {
    sheet.set_panes(
      Split(x=panes.x_split.to_double(), y=panes.y_split.to_double()),
    )
  }
  let view = backend.get_sheet_view(sheet.name, LAST_SHEET_VIEW)
  // Only the non-default is worth writing: Excel shows gridlines.
  if view.show_grid_lines is Some(false) {
    sheet.set_gridlines(false)
  }
  let props = backend.get_sheet_props(sheet.name)
  // A tab is coloured from the theme as often as from a literal RGB — the
  // colour picker offers the theme row first — so it resolves through the same
  // path a font or a fill does.
  if resolve_color(
      backend,
      props.tab_color_rgb,
      theme=props.tab_color_theme,
      indexed=props.tab_color_indexed,
      tint=props.tab_color_tint,
      what="a sheet tab's",
      notes~,
    )
    is Some(color) {
    sheet.set_tab_color(color)
  }
}

///|
/// The backend indexes a sheet's views; `-1` addresses the last one. This has to
/// match the index `emit` writes to — the two packages are the only ones that
/// speak to the backend, and there is no third place for a constant they share.
const LAST_SHEET_VIEW : Int = -1

///|
/// **Page setup is not recovered**, and this is where it would be.
///
/// The backend cannot answer per sheet: `page_layout_with_defaults` (and its
/// margins twin) aliases a module-level default rather than copying it, then
/// writes the sheet's own values into it — so reading one sheet's setup leaves
/// every later sheet, and every later workbook read in the same process,
/// reporting that sheet's orientation and scaling. A spec built on that would
/// put `orientation: landscape` on sheets that print portrait.
///
/// So it is refused by name rather than guessed at, as the workbook-level
/// `protect:` was. `render` still writes a `print:` block for any model that
/// carries one; it is only this direction that has nothing trustworthy to fill
/// it with. Becomes a plain read again the day the alias is a copy.
