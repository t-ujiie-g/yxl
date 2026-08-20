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

///|
/// A style that only takes attributes away.
fn clears(attrs : Array[@model.StyleAttr]) -> @model.Style {
  @model.Style::empty().clearing(@model.StyleAttrs::of(attrs))
}

///|
/// A style setting only a fill.
fn filled(hex : String) -> @model.Style {
  {
    ..@model.Style::empty(),
    fill: Some({ color: @units.Color::parse(hex).unwrap() }),
  }
}

///|
/// The fill a cell is actually drawn with, as the reader reports it.
fn cell_fill(wb : @model.Workbook, reference : String) -> String? raise {
  let reopened = reopen(wb)
  guard reopened.get_cell_style("S", reference) is Some(id) else { return None }
  match reopened.get_style(id).fill {
    Some(fill) =>
      match fill.colors {
        Some(colors) if !colors.is_empty() => Some(colors[0])
        _ => None
      }
    None => None
  }
}

///|
test "a cell that clears the band's fill is drawn unfilled" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=3, last=3, style=filled("FFF2CC"))
  sheet.set(@units.CellRef::new(col=3, row=1), Number(1.0))
  sheet.set(
    @units.CellRef::new(col=3, row=2),
    Number(2.0),
    style=clears([Fill]),
  )
  assert_eq(cell_fill(wb, "C1"), Some("FFF2CC"))
  assert_eq(cell_fill(wb, "C2"), None)
}

///|
test "clearing one attribute leaves the band's others in place" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=2, style={
    ..formatted("#,##0"),
    font: bold().font,
  })
  sheet.set(
    @units.CellRef::new(col=2, row=1),
    Number(1.0),
    style=clears([NumberFormat]),
  )
  assert_eq(cell_format(wb, "B1"), None)
  assert_true(cell_is_bold(wb, "B1"))
}

///|
test "a row band clears what the column band under it set" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=2, last=2, style=formatted("#,##0"))
  sheet.set_row_band(first=1, last=1, style=clears([NumberFormat]))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(1.0))
  sheet.set(@units.CellRef::new(col=2, row=2), Number(2.0))
  assert_eq(cell_format(wb, "B1"), None)
  assert_eq(cell_format(wb, "B2"), Some("#,##0"))
}

///|
test "a cell that clears everything the band gave it wears the default style" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=3, last=3, style=filled("FFF2CC"))
  sheet.set(
    @units.CellRef::new(col=3, row=1),
    Number(1.0),
    style=clears([Fill]),
  )
  // Style 0 is the default every unstyled cell carries.
  assert_true(reopen(wb).get_cell_style("S", "C1") is (None | Some(0)))
}
