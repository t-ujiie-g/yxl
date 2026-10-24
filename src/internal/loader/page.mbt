///|
/// A sheet's `print:` block. Every key is optional; `scale` and `fit` are
/// Excel's two exclusive halves of one control.
fn load_page_setup(
  node : @yaml.Node,
  file~ : String,
  defs~ : Defs,
  sheet~ : String,
) -> @model.PageSetup raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="sheet 'print'")
  // Excel scales by a percentage or by a page fit, and they share one model
  // field, so declaring both would silently drop one.
  guard !(find_key(entries, "scale") is Some(_) &&
    find_key(entries, "fit") is Some(_)) else {
    raise schema_error(
      file~,
      "sheet 'print' cannot combine 'scale' and 'fit' (Excel scales by one or the other)",
    )
  }
  let mut area = None
  let mut orientation = None
  let mut margins = None
  let mut scale = None
  let mut header = None
  let mut footer = None
  let mut breaks = []
  let mut title_rows = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "area" => {
        let text = expect_string(value, file~, context="print 'area'")
        area = Some(
          match layout_here(text, defs~, sheet~, file~, what="print area") {
            Some(layout) => layout_extent(layout)
            None => parse_range(text, file~, what="print area")
          },
        )
      }
      "titles" =>
        title_rows = Some(load_title_rows(value, file~, defs~, sheet~))
      "orientation" => orientation = Some(load_orientation(value, file~))
      "margins" => margins = Some(load_margins(value, file~))
      "scale" => scale = Some(load_scale(value, file~))
      "fit" => scale = Some(load_fit(value, file~))
      "header" =>
        header = Some(expect_string(value, file~, context="print 'header'"))
      "footer" =>
        footer = Some(expect_string(value, file~, context="print 'footer'"))
      "breaks" => breaks = load_breaks(value, file~)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet 'print' (expected 'area', 'orientation', 'margins', 'scale', 'fit', 'header', 'footer', 'breaks', or 'titles')",
        )
    }
  }
  { area, orientation, margins, scale, header, footer, breaks, title_rows, }
}

///|
/// A `print.titles:` — a row, a `first-last` span, or a layout, whose header
/// rows repeat.
fn load_title_rows(
  node : @yaml.Node,
  file~ : String,
  defs~ : Defs,
  sheet~ : String,
) -> @model.TitleRows raise @diag.SchemaError {
  let text = match node {
    @yaml.Str(text) => text
    @yaml.Int(row) => row.to_string()
    _ =>
      raise schema_error(
        file~,
        "print 'titles' must be a row, a 'first-last' span, or a layout",
      )
  }
  if layout_here(text, defs~, sheet~, file~, what="print titles")
    is Some(layout) {
    guard layout.header_row is Some(last) else {
      raise schema_error(
        file~,
        "print titles '\{text}' names a layout with no header rows to repeat",
      )
    }
    return { first: layout.header_first, last, }
  }
  let (first, last) = parse_row_selector(text, file~)
  { first, last, }
}

///|
/// A `print.orientation:` — which way the paper runs.
fn load_orientation(
  node : @yaml.Node,
  file~ : String,
) -> @model.Orientation raise @diag.SchemaError {
  match expect_string(node, file~, context="print 'orientation'") {
    "portrait" => Portrait
    "landscape" => Landscape
    other =>
      raise schema_error(
        file~,
        "unknown print orientation '\{other}' (expected 'portrait' or 'landscape')",
      )
  }
}

///|
/// A `print.scale:` percentage of actual size, within Excel's range.
fn load_scale(
  node : @yaml.Node,
  file~ : String,
) -> @model.PageScale raise @diag.SchemaError {
  guard node is @yaml.Int(percent) else {
    raise schema_error(file~, "print 'scale' must be a whole number of percent")
  }
  guard percent >= @model.min_page_scale.to_int64() &&
    percent <= @model.max_page_scale.to_int64() else {
    raise schema_error(
      file~,
      "print 'scale' must be between \{@model.min_page_scale} and \{@model.max_page_scale} percent",
    )
  }
  Percent(percent.to_int())
}

///|
/// A `print.fit: { width, height }` — how many pages across and down the sheet
/// is shrunk to fit. An axis left out (or `0`) is unconstrained; constraining
/// neither would scale nothing.
fn load_fit(
  node : @yaml.Node,
  file~ : String,
) -> @model.PageScale raise @diag.SchemaError {
  let mut width = 0
  let mut height = 0
  for entry in expect_map(node, file~, context="print 'fit'") {
    let (key, value) = entry
    match key {
      "width" => width = expect_page_count(value, file~, what="width")
      "height" => height = expect_page_count(value, file~, what="height")
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in print 'fit' (expected 'width' or 'height')",
        )
    }
  }
  guard width > 0 || height > 0 else {
    raise schema_error(
      file~,
      "print 'fit' needs a non-zero 'width' or 'height' (in pages)",
    )
  }
  Fit(width~, height~)
}

///|
/// A page count in a `fit` axis: a whole number of pages, never negative.
fn expect_page_count(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> Int32 raise @diag.SchemaError {
  guard node is @yaml.Int(pages) && pages >= 0L else {
    raise schema_error(
      file~,
      "print 'fit' \{what} must be a whole number of pages (0 for unconstrained)",
    )
  }
  pages.to_int()
}

///|
/// A `print.margins:` mapping, in inches — Excel's unit for these. A negative
/// margin is meaningless, so it is a diagnostic.
fn load_margins(
  node : @yaml.Node,
  file~ : String,
) -> @model.PageMargins raise @diag.SchemaError {
  let mut margins = @model.PageMargins::{
    top: None,
    bottom: None,
    left: None,
    right: None,
    header: None,
    footer: None,
  }
  for entry in expect_map(node, file~, context="print 'margins'") {
    let (key, value) = entry
    let inches = expect_number(value, file~, context="print margin '\{key}'")
    guard inches >= 0.0 else {
      raise schema_error(file~, "print margin '\{key}' cannot be negative")
    }
    match key {
      "top" => margins = { ..margins, top: Some(inches), }
      "bottom" => margins = { ..margins, bottom: Some(inches), }
      "left" => margins = { ..margins, left: Some(inches), }
      "right" => margins = { ..margins, right: Some(inches), }
      "header" => margins = { ..margins, header: Some(inches), }
      "footer" => margins = { ..margins, footer: Some(inches), }
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in print 'margins' (expected 'top', 'bottom', 'left', 'right', 'header', or 'footer')",
        )
    }
  }
  margins
}

///|
/// A `print.breaks:` sequence of cells, each starting a new page above and to
/// the left of itself. `A1` starts no page, so it is a mistake worth reporting.
fn load_breaks(
  node : @yaml.Node,
  file~ : String,
) -> Array[@units.CellRef] raise @diag.SchemaError {
  let breaks = []
  for item in expect_seq(node, file~, context="print 'breaks'") {
    let reference = expect_string(item, file~, context="a print break")
    let cell = expect_cell_ref(reference, file~, what="print 'breaks'")
    guard cell.col > 1 || cell.row > 1 else {
      raise schema_error(file~, "a print break at 'A1' would break nothing")
    }
    breaks.push(cell)
  }
  breaks
}
