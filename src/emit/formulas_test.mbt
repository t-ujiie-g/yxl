///|
/// A sheet with two columns of numbers, ready for a calculation column beside
/// them.
fn calculation_sheet() -> (@model.Workbook, @model.Sheet) {
  let (wb, sheet) = fixture()
  for row in 1..<=3 {
    sheet.set(@units.CellRef::new(col=1, row~), Number(row.to_double()))
    sheet.set(@units.CellRef::new(col=2, row~), Number(10.0))
  }
  (wb, sheet)
}

///|
/// A range spanning `top_left`..`bottom_right`, both given as A1 text.
fn range_of(top_left : String, bottom_right : String) -> @model.CellRange {
  {
    top_left: @units.CellRef::parse_a1(top_left).unwrap(),
    bottom_right: @units.CellRef::parse_a1(bottom_right).unwrap(),
  }
}

///|
test "a filled range stores the formula once, on the master cell" {
  let (wb, sheet) = calculation_sheet()
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", })
  let reopened = reopen(wb)
  // The master carries the text; the followers carry no formula text at all,
  // only their membership of the master's range, so the range costs one stored
  // formula however many rows it covers (ADR-004). Excel derives each
  // follower's formula from the master when it opens the file.
  assert_eq(reopened.get_cell_formula("S", "C1"), Some("A1*B1"))
  assert_eq(reopened.get_cell_formula("S", "C2"), None)
  assert_eq(reopened.get_cell_formula("S", "C3"), None)
}

///|
test "a filled range costs one stored formula, whatever it covers" {
  let (wb, sheet) = calculation_sheet()
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", })
  // `formula_refs` lists the cells that hold formula *text*: three cells
  // calculate, one of them stores anything (ADR-004).
  assert_eq(reopen(wb).sheet("S").unwrap().formula_refs(), ["C1"])
}

///|
test "two ranges on one sheet stay separate formulas" {
  let (wb, sheet) = calculation_sheet()
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", })
  sheet.add_formula({ at: range_of("D1", "D3"), formula: "C1+1", })
  let reopened = reopen(wb)
  assert_eq(reopened.get_cell_formula("S", "C1"), Some("A1*B1"))
  assert_eq(reopened.get_cell_formula("S", "D1"), Some("C1+1"))
  // Six calculating cells, two stored formulas — one master each.
  assert_eq(reopened.sheet("S").unwrap().formula_refs(), ["C1", "D1"])
}

///|
test "a single-cell range is an ordinary formula in one cell" {
  let (wb, sheet) = calculation_sheet()
  sheet.add_formula({ at: range_of("C1", "C1"), formula: "A1*B1", })
  assert_eq(reopen(wb).get_cell_formula("S", "C1"), Some("A1*B1"))
}

///|
test "a band formats every cell a filled range covers, master and followers" {
  let (wb, sheet) = calculation_sheet()
  sheet.set_column_band(first=3, last=3, style={
    ..@model.Style::empty(),
    number_format: Some("0.00"),
  })
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", })
  // `formulas:` carries no styling of its own, for the same reason `data:` does
  // not — a band is where formatting belongs, and that is what keeps the two
  // separable. So the band has to reach *these* cells, including the followers
  // that hold no formula text: a calculation column formatted only on its first
  // row would be worse than one formatted on none.
  for reference in ["C1", "C2", "C3"] {
    assert_eq(cell_format(wb, reference), Some("0.00"))
  }
}

///|
test "a filled range outside every band leaves its cells unstyled" {
  let (wb, sheet) = calculation_sheet()
  sheet.set_column_band(first=4, last=4, style={
    ..@model.Style::empty(),
    number_format: Some("0.00"),
  })
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", })
  assert_eq(cell_format(wb, "C1"), None)
  assert_eq(cell_format(wb, "C2"), None)
}

///|
test "a row band reaches a filled range that crosses it" {
  let (wb, sheet) = calculation_sheet()
  sheet.set_row_band(first=2, last=2, style={
    ..@model.Style::empty(),
    number_format: Some("0.0%"),
  })
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", })
  assert_eq(cell_format(wb, "C1"), None)
  assert_eq(cell_format(wb, "C2"), Some("0.0%"))
  assert_eq(cell_format(wb, "C3"), None)
}
