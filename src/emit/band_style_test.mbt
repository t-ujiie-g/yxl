// Round-trip tests for the styling a column or row band passes down to the
// cells inside it. These read the *cell's* style back, which is the point: a
// band's style on the column record alone governs only the cells nobody wrote
// (ECMA-376 §18.3.1.13), so a test that asserted the column record would pass
// while every written cell went unstyled.

///|
/// A style setting only a number format.
fn formatted(code : String) -> @model.Style {
  { ..@model.Style::empty(), number_format: Some(code) }
}

///|
/// A style setting only bold.
fn bold() -> @model.Style {
  {
    ..@model.Style::empty(),
    font: Some({ ..@model.Font::empty(), bold: Some(true) }),
  }
}

///|
/// The number format a cell is actually drawn with, as the reader reports it.
fn cell_format(wb : @model.Workbook, reference : String) -> String? raise {
  let reopened = reopen(wb)
  guard reopened.get_cell_style("S", reference) is Some(id) else { return None }
  match reopened.get_style(id).number_format {
    Some(Custom(code)) => Some(code)
    _ => None
  }
}

///|
/// Whether the cell is drawn bold, as the reader reports it.
fn cell_is_bold(wb : @model.Workbook, reference : String) -> Bool raise {
  let reopened = reopen(wb)
  guard reopened.get_cell_style("S", reference) is Some(id) else {
    return false
  }
  match reopened.get_style(id).font {
    Some(font) => font.bold is Some(true)
    None => false
  }
}

///|
test "a column band's format reaches the cells written in that column" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=2, style=formatted("#,##0"))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(2400000.0))
  assert_eq(cell_format(wb, "B1"), Some("#,##0"))
}

///|
test "a row band's style reaches the cells written in that row" {
  let (wb, sheet) = fixture()
  sheet.set_row_band(first=1, last=1, style=bold())
  sheet.set(@units.CellRef::new(col=1, row=1), Text("Region"))
  assert_true(cell_is_bold(wb, "A1"))
}

///|
test "a cell keeps its own style, layered over the bands it sits in" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=2, style=formatted("#,##0"))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(1.0), style=bold())
  // The band supplies the format, the cell the font: the two merge rather than
  // one replacing the other.
  assert_eq(cell_format(wb, "B1"), Some("#,##0"))
  assert_true(cell_is_bold(wb, "B1"))
}

///|
test "a cell's own format wins over the band's" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=2, style=formatted("#,##0"))
  sheet.set(
    @units.CellRef::new(col=2, row=1),
    Number(1.0),
    style=formatted("0.0%"),
  )
  assert_eq(cell_format(wb, "B1"), Some("0.0%"))
}

///|
test "a row band lies over a column band where they cross" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=2, style=formatted("#,##0"))
  sheet.set_row_band(first=1, last=1, style=formatted("0.0%"))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(1.0))
  assert_eq(cell_format(wb, "B1"), Some("0.0%"))
}

///|
test "an inherited number format does not reach a text cell" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=2, style=formatted("#,##0"))
  sheet.set(@units.CellRef::new(col=2, row=1), Text("Revenue"))
  // Excel ignores a numeric format on text, so inheriting it would change
  // nothing — and the backend would render the header as the literal `#,##0`,
  // which is how a pivot loses the field it looks up by that name.
  assert_eq(cell_format(wb, "B1"), None)
  assert_eq(reopen(wb).get_cell_value("S", "B1"), Some("Revenue"))
}

///|
test "a band's other attributes still reach a text cell" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=2, style=bold())
  sheet.set(@units.CellRef::new(col=2, row=1), Text("Region"))
  assert_true(cell_is_bold(wb, "B1"))
}

///|
test "a format with a text section does reach a text cell" {
  let (wb, sheet) = fixture()
  // Four sections: positive;negative;zero;text — the fourth is Excel's own way
  // of formatting text, so it is inherited like anything else.
  sheet.set_column_band(
    first=2,
    last=2,
    style=formatted("#,##0;-#,##0;0;\"n/a\""),
  )
  sheet.set(@units.CellRef::new(col=2, row=1), Text("Region"))
  assert_eq(cell_format(wb, "B1"), Some("#,##0;-#,##0;0;\"n/a\""))
}

///|
test "a format is still honoured on a text cell that asked for it itself" {
  let (wb, sheet) = fixture()
  // Only *inheritance* is filtered; writing `format:` on the cell is a request.
  sheet.set(
    @units.CellRef::new(col=2, row=1),
    Text("Region"),
    style=formatted("#,##0"),
  )
  assert_eq(cell_format(wb, "B1"), Some("#,##0"))
}

///|
test "a band reaches only the columns and rows it spans" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=3, style=formatted("#,##0"))
  for col in 1..<=4 {
    sheet.set(@units.CellRef::new(col~, row=1), Number(1.0))
  }
  assert_eq(cell_format(wb, "A1"), None)
  assert_eq(cell_format(wb, "B1"), Some("#,##0"))
  assert_eq(cell_format(wb, "C1"), Some("#,##0"))
  assert_eq(cell_format(wb, "D1"), None)
}
