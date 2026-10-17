///|
/// How the sheet prints, the inverse of `emit`'s `apply_page_setup`. Values
/// equal to Excel's defaults are dropped, so an untouched sheet gets no `print:`.
fn read_page_setup(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit {
  guard backend.sheet(sheet.name) is Some(source) else { return }
  let page : @model.PageSetup = {
    area: print_area(backend, sheet.name, notes),
    orientation: source.page_layout.bind(layout => orientation(layout, notes)),
    margins: source.page_margins.bind(margins => page_margins(margins, notes)),
    scale: page_scale(source, notes),
    header: source.header_footer.bind(hf => non_empty(hf.odd_header)),
    footer: source.header_footer.bind(hf => non_empty(hf.odd_footer)),
    breaks: page_breaks(source),
    title_rows: print_titles(backend, sheet.name, notes),
  }
  if source.header_footer is Some(hf) &&
    (hf.different_first || hf.different_odd_even) {
    notes.drop(
      "a different header or footer on the first page or on even pages, of which the spec keeps only the ordinary one",
    )
  }
  if page != @model.PageSetup::empty() {
    sheet.set_page_setup(page)
  }
}

///|
/// The sheet's `_xlnm.Print_Area` (ECMA-376 §18.2.6), when it is one range on
/// this sheet.
fn print_area(
  backend : @xlsx.Workbook,
  sheet_name : String,
  notes : Notes,
) -> @model.CellRange? {
  for defined in backend.get_defined_names() {
    guard defined.name == @model.print_area_name && defined.scope == sheet_name else {
      continue
    }
    guard parse_sheet_range(defined.refers_to)
      is Some({ sheet: Some(target), range, }) &&
      target == sheet_name else {
      notes.drop(
        "a print area of more than one range, or on another sheet, which the spec writes as one range on its own sheet",
      )
      return None
    }
    return Some(range)
  }
  None
}

///|
/// The sheet's `_xlnm.Print_Titles` (ECMA-376 §18.2.6), when it repeats rows
/// alone: `'S'!$1:$3`.
fn print_titles(
  backend : @xlsx.Workbook,
  sheet_name : String,
  notes : Notes,
) -> @model.TitleRows? {
  for defined in backend.get_defined_names() {
    guard defined.name == @model.print_titles_name &&
      defined.scope == sheet_name else {
      continue
    }
    guard @model.split_sheet_prefix(defined.refers_to)
      is Some((Some(target), rows)) &&
      target == sheet_name &&
      title_row_span(rows) is Some(span) else {
      notes.drop(
        "print titles repeating columns, or on another sheet, which the spec writes as rows of its own sheet",
      )
      return None
    }
    return Some(span)
  }
  None
}

///|
/// `$1:$3` as rows 1 to 3.
fn title_row_span(text : String) -> @model.TitleRows? {
  guard text.find(":") is Some(colon) else { return None }
  let row = (part : StringView) => {
    let digits = if part.has_prefix("$") { part[1:] } else { part }
    match @units.parse_uint(digits) {
      Some(value) if value >= 1 => Some(value)
      _ => None
    }
  }
  guard row(text[:colon]) is Some(first) &&
    row(text[colon + 1:]) is Some(last) &&
    first <= last else {
    return None
  }
  Some({ first, last, })
}

///|
fn orientation(
  layout : @xlsx.PageLayoutOptions,
  notes : Notes,
) -> @model.Orientation? {
  if layout.size is Some(size) && size > 1 {
    notes.drop("a paper size other than Letter, which the spec has no word for")
  }
  if layout.first_page_number is Some(first) && first != 1 {
    notes.drop("a first page number, which the spec has no word for")
  }
  if layout.black_and_white is Some(true) {
    notes.drop("black-and-white printing, which the spec has no word for")
  }
  if layout.page_order is Some("overThenDown") {
    notes.drop("an over-then-down page order, which the spec has no word for")
  }
  match layout.orientation {
    Some("landscape") => Some(Landscape)
    _ => None
  }
}

///|
/// Each margin that differs from Excel's own (ECMA-376 §18.3.1.62's defaults as
/// Excel writes them), or `None` when none does.
fn page_margins(
  margins : @xlsx.PageLayoutMarginsOptions,
  notes : Notes,
) -> @model.PageMargins? {
  if margins.horizontally is Some(true) || margins.vertically is Some(true) {
    notes.drop("centring on the page, which the spec has no word for")
  }
  let unless = (value : Double?, default : Double) => {
    value.filter(v => v != default)
  }
  let recovered : @model.PageMargins = {
    top: unless(margins.top, 0.75),
    bottom: unless(margins.bottom, 0.75),
    left: unless(margins.left, 0.7),
    right: unless(margins.right, 0.7),
    header: unless(margins.header, 0.3),
    footer: unless(margins.footer, 0.3),
  }
  guard recovered.top is Some(_) ||
    recovered.bottom is Some(_) ||
    recovered.left is Some(_) ||
    recovered.right is Some(_) ||
    recovered.header is Some(_) ||
    recovered.footer is Some(_) else {
    return None
  }
  Some(recovered)
}

///|
/// Fit-to-pages where the sheet is flagged for it — without the flag Excel
/// ignores `fitToWidth`/`fitToHeight`, whose omitted default is 1 — else a
/// percentage other than 100.
fn page_scale(source : @xlsx.Worksheet, notes : Notes) -> @model.PageScale? {
  let layout = source.page_layout
  if source.sheet_props is Some({ fit_to_page: Some(true), .. }) {
    let width = layout.bind(l => l.fit_to_width).unwrap_or(1)
    let height = layout.bind(l => l.fit_to_height).unwrap_or(1)
    return Some(Fit(width~, height~))
  }
  match layout.bind(l => l.adjust_to) {
    Some(100) | None => None
    Some(percent) if percent >= @model.min_page_scale &&
      percent <= @model.max_page_scale => Some(Percent(percent))
    Some(_) => {
      notes.drop("a print scale outside Excel's 10–400%")
      None
    }
  }
}

///|
/// Manual breaks as the cells the schema names them by. A row break and a
/// column break each come back on their own cell, `A<n>` and `<col>1`, which
/// compiles to the same breaks as one cell carrying both.
fn page_breaks(source : @xlsx.Worksheet) -> Array[@units.CellRef] {
  let breaks = []
  for brk in source.row_breaks {
    if brk.manual && brk.id > 0 {
      breaks.push(@units.CellRef(col=1, row=brk.id + 1))
    }
  }
  for brk in source.col_breaks {
    if brk.manual && brk.id > 0 {
      breaks.push(@units.CellRef(col=brk.id + 1, row=1))
    }
  }
  breaks
}
