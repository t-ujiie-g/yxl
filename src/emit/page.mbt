// The print half of the emitter: Excel scatters a sheet's page setup across
// three unrelated OOXML places (page setup, margins, header/footer) and stores
// the print area as a built-in *defined name* rather than a sheet setting, so
// one `@model.PageSetup` fans out into four backend calls. The matching spec
// block is parsed in the loader's `page.mbt`.

///|
/// Excel's built-in defined name for a sheet's print area (ECMA-376 §18.2.5);
/// scoping it to the sheet is what makes it that sheet's area.
const PRINT_AREA_NAME : String = "_xlnm.Print_Area"

///|
/// Drive the backend's page-setup surface for one sheet: paper layout, margins,
/// header/footer, manual breaks, and the print area.
fn apply_page_setup(
  backend : @xlsx.Workbook,
  sheet_name : String,
  page : @model.PageSetup,
) -> Unit raise {
  let orientation = page.orientation.map(orientation_code)
  let (adjust_to, fit_to_width, fit_to_height) = match page.scale {
    Some(Percent(percent)) => (Some(percent), None, None)
    Some(Fit(width~, height~)) => (None, Some(width), Some(height))
    None => (None, None, None)
  }
  if orientation is Some(_) || page.scale is Some(_) {
    backend.set_page_layout(
      sheet_name,
      Some(
        @xlsx.PageLayoutOptions::with_values(
          orientation?,
          adjust_to?,
          fit_to_width?,
          fit_to_height?,
        ),
      ),
    )
  }
  // Excel ignores fitToWidth/fitToHeight unless the sheet is flagged fit-to-page.
  if page.scale is Some(Fit(..)) {
    backend.set_sheet_props(
      sheet_name,
      Some(@xlsx.SheetPropsOptions::with_values(fit_to_page=true)),
    )
  }
  if page.margins is Some(margins) {
    backend.set_page_margins(
      sheet_name,
      Some(
        @xlsx.PageLayoutMarginsOptions::with_values(
          top?=margins.top,
          bottom?=margins.bottom,
          left?=margins.left,
          right?=margins.right,
          header?=margins.header,
          footer?=margins.footer,
        ),
      ),
    )
  }
  if page.header is Some(_) || page.footer is Some(_) {
    backend.set_header_footer(
      sheet_name,
      Some(
        @xlsx.HeaderFooterOptions::with_values(
          odd_header?=page.header,
          odd_footer?=page.footer,
        ),
      ),
    )
  }
  for at in page.breaks {
    backend.insert_page_break(sheet_name, at.to_a1())
  }
  if page.area is Some(area) {
    backend.set_defined_name(
      @xlsx.DefinedName::new(
        PRINT_AREA_NAME,
        absolute_range(sheet_name, area),
        scope=sheet_name,
      ),
    )
  }
}

///|
/// A range as the absolute, sheet-qualified reference Excel stores a print area
/// as: `'Sheet 1'!$A$1:$D$20`. A quote inside a sheet name is doubled.
fn absolute_range(sheet_name : String, range : @model.CellRange) -> String {
  quoted_sheet(sheet_name) +
  "!" +
  range.top_left.to_absolute_a1() +
  ":" +
  range.bottom_right.to_absolute_a1()
}

///|
/// A sheet name as a reference quotes it. Excel quotes every name it writes
/// itself, whether or not the name needs it, and doubles an inner quote.
fn quoted_sheet(sheet_name : String) -> String {
  "'" + sheet_name.replace_all(old="'", new="''") + "'"
}

///|
/// The OOXML page-orientation attribute for a model `Orientation`.
fn orientation_code(orientation : @model.Orientation) -> String {
  match orientation {
    Portrait => "portrait"
    Landscape => "landscape"
  }
}
