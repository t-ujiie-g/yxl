///|
test "a fresh workbook has no sheets" {
  assert_eq(@model.Workbook::new().sheets.length(), 0)
}

///|
test "add_sheet appends a sheet whose edits are visible in the workbook" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("Sheet1")
  sheet.set(@units.CellRef::new(col=1, row=1), Text("yxl"))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(42.0), format="0.00")
  // The returned sheet shares the workbook's storage: edits land in the workbook.
  assert_eq(wb.sheets.length(), 1)
  assert_eq(wb.sheets[0].name, "Sheet1")
  assert_eq(wb.sheets[0].cells.length(), 2)
  assert_eq(wb.sheets[0].cells[0], {
    pos: @units.CellRef::new(col=1, row=1),
    value: Text("yxl"),
    style: None,
  })
  assert_eq(wb.sheets[0].cells[1].value, Number(42.0))
  assert_eq(
    wb.sheets[0].cells[1].style,
    Some(@model.Style::number_format("0.00")),
  )
}

///|
test "set folds a format shorthand into a style, and merges with an explicit style" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  let bold : @model.Style = {
    ..@model.Style::empty(),
    font: Some({
      bold: Some(true),
      italic: None,
      underline: None,
      strike: None,
      size: None,
      name: None,
      color: None,
    }),
  }
  // A `format` shorthand alone becomes a number-format-only style.
  sheet.set(@units.CellRef::new(col=1, row=1), Number(1.0), format="0%")
  assert_eq(sheet.cells[0].style, Some(@model.Style::number_format("0%")))
  // A `format` fills in a style that leaves the number format unset.
  sheet.set(
    @units.CellRef::new(col=2, row=1),
    Number(1.0),
    format="0%",
    style=bold,
  )
  assert_eq(sheet.cells[1].style, Some({ ..bold, number_format: Some("0%") }))
  // An empty style with no format is dropped entirely.
  sheet.set(
    @units.CellRef::new(col=3, row=1),
    Number(1.0),
    style=@model.Style::empty(),
  )
  assert_eq(sheet.cells[2].style, None)
}

///|
test "Style::is_empty distinguishes the default style from any set attribute" {
  assert_true(@model.Style::empty().is_empty())
  assert_false(@model.Style::number_format("0.00").is_empty())
  assert_false(
    @model.Style::{ ..@model.Style::empty(), fill: Some({ color: red() }) }.is_empty(),
  )
}

///|
test "Style::over keeps what the overriding style leaves unset" {
  let base : @model.Style = {
    font: Some({
      bold: Some(false),
      italic: None,
      underline: None,
      strike: None,
      size: Some(11.0),
      name: Some("Calibri"),
      color: None,
    }),
    fill: Some({ color: red() }),
    borders: Some({
      left: Some({ style: Thin, color: None }),
      right: None,
      top: None,
      bottom: None,
    }),
    align: Some({ horizontal: Some(Left), vertical: None, wrap: Some(true) }),
    number_format: Some("0.00"),
    protection: None,
  }
  let over : @model.Style = {
    ..@model.Style::empty(),
    font: Some({
      bold: Some(true),
      italic: None,
      underline: None,
      strike: None,
      size: None,
      name: None,
      color: None,
    }),
    align: Some({ horizontal: Some(Center), vertical: None, wrap: None }),
  }
  let merged = over.over(base)
  let font = merged.font.unwrap()
  // The merge reaches inside the font: `bold` is overridden, the rest shows
  // through.
  assert_eq(font.bold, Some(true))
  assert_eq(font.size, Some(11.0))
  assert_eq(font.name, Some("Calibri"))
  assert_eq(merged.align.unwrap().horizontal, Some(Center))
  assert_eq(merged.align.unwrap().wrap, Some(true))
  // Untouched parts of the base survive whole.
  assert_eq(merged.fill, base.fill)
  assert_eq(merged.borders, base.borders)
  assert_eq(merged.number_format, Some("0.00"))
  // Over the empty style, either side is itself.
  assert_eq(over.over(@model.Style::empty()), over)
  assert_eq(@model.Style::empty().over(base), base)
}

///|
test "band setters record an inclusive span and only the properties given" {
  let sheet = @model.Sheet::new("S")
  sheet.set_column_band(first=2, last=4, width=12.0, hidden=true)
  sheet.set_row_band(first=1, last=1, height=24.0, outline_level=2)
  assert_eq(sheet.columns, [
    {
      first: 2,
      last: 4,
      style: None,
      size: Some(12.0),
      hidden: Some(true),
      outline_level: None,
    },
  ])
  assert_eq(sheet.rows, [
    {
      first: 1,
      last: 1,
      style: None,
      size: Some(24.0),
      hidden: None,
      outline_level: Some(2),
    },
  ])
  // A band that sets nothing is still a band; dropping empties is the loader's
  // job, not the model's.
  sheet.set_column_band(first=9, last=9)
  assert_eq(sheet.columns.length(), 2)
}

///|
test "merge canonicalizes its corners whichever pair is given" {
  let sheet = @model.Sheet::new("S")
  // Bottom-right first, then top-right — both name the same rectangle.
  sheet.merge(
    @units.CellRef::new(col=3, row=3),
    @units.CellRef::new(col=1, row=1),
  )
  sheet.merge(
    @units.CellRef::new(col=3, row=1),
    @units.CellRef::new(col=1, row=3),
  )
  let expected : @model.CellRange = {
    top_left: @units.CellRef::new(col=1, row=1),
    bottom_right: @units.CellRef::new(col=3, row=3),
  }
  assert_eq(sheet.merges, [expected, expected])
}

///|
test "sheet presentation setters are independent and default to Excel's own" {
  let sheet = @model.Sheet::new("S")
  // Untouched, every presentation property defers to Excel.
  assert_eq(sheet.visibility, Visible)
  assert_eq(sheet.panes, None)
  assert_eq(sheet.gridlines, None)
  assert_eq(sheet.tab_color, None)
  assert_eq(sheet.page, None)
  sheet.set_panes(Freeze(@units.CellRef::new(col=2, row=2)))
  sheet.set_gridlines(false)
  sheet.set_tab_color(red())
  sheet.set_page_setup({
    ..@model.PageSetup::empty(),
    orientation: Some(Landscape),
  })
  assert_eq(sheet.panes, Some(Freeze(@units.CellRef::new(col=2, row=2))))
  assert_eq(sheet.gridlines, Some(false))
  assert_eq(sheet.tab_color, Some(red()))
  assert_eq(sheet.page.unwrap().orientation, Some(Landscape))
  // A hidden sheet is declared at construction, not mutated in.
  assert_eq(
    @model.Sheet::new("H", visibility=VeryHidden).visibility,
    VeryHidden,
  )
}

///|
test "PageSetup::empty changes nothing" {
  let page = @model.PageSetup::empty()
  assert_eq(page.area, None)
  assert_eq(page.orientation, None)
  assert_eq(page.margins, None)
  assert_eq(page.scale, None)
  assert_eq(page.header, None)
  assert_eq(page.footer, None)
  assert_eq(page.breaks, [])
}

///|
test "defined names and the active sheet are workbook-wide, in declaration order" {
  let wb = @model.Workbook::new()
  assert_eq(wb.active_sheet, None)
  wb.add_defined_name("tax_rate", Number(0.08))
  wb.add_defined_name("company", Text("Acme"))
  assert_eq(wb.defined_names, [
    { name: "tax_rate", refers_to: Number(0.08) },
    { name: "company", refers_to: Text("Acme") },
  ])
  wb.add_sheet("S") |> ignore
  wb.set_active_sheet("S")
  assert_eq(wb.active_sheet, Some("S"))
}

///|
/// A color for the tests that need one; `parse` is exercised in `units`.
fn red() -> @units.Color {
  @units.Color::parse("FF0000").unwrap()
}

///|
test "cells keep insertion order across multiple sheets" {
  let wb = @model.Workbook::new()
  let s1 = wb.add_sheet("First")
  let s2 = wb.add_sheet("Second")
  s2.set(@units.CellRef::new(col=1, row=1), Text("b"))
  s1.set(@units.CellRef::new(col=1, row=1), Text("a"))
  assert_eq(wb.sheets.map(s => s.name), ["First", "Second"])
  assert_eq(wb.sheets[0].cells[0].value, Text("a"))
  assert_eq(wb.sheets[1].cells[0].value, Text("b"))
}
