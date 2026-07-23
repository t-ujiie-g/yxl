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
