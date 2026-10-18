///|
/// An override of `at`, given as A1 on the fixture's sheet.
fn override_at(
  at : String,
  value? : @model.CellValue,
  style? : @model.Style,
) -> @model.Override {
  {
    sheet: "S",
    at: @units.CellRef::parse_a1(at).unwrap(),
    value,
    style,
    reason: None,
  }
}

///|
test "an override replaces the value the sheet already wrote" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef(col=1, row=1), Text("from the template"))
  wb.add_override(override_at("A1", value=Text("by hand")))
  assert_eq(reopen(wb).get_cell_value("S", "A1"), Some("by hand"))
}

///|
test "an override wins wherever the spec declared it" {
  let (wb, sheet) = fixture()
  // The override is registered *before* the cell it overrides, which is the
  // whole reason the layer exists: `cells:` after `data:` wins by key order, and
  // key order is what a reformatting tool is free to change (ADR-018).
  wb.add_override(override_at("A1", value=Text("by hand")))
  sheet.set(@units.CellRef(col=1, row=1), Text("from the template"))
  assert_eq(reopen(wb).get_cell_value("S", "A1"), Some("by hand"))
}

///|
test "a value-only override keeps the style the cell already had" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=formatted("0.00"))
  wb.add_override(override_at("A1", value=Number(2.0)))
  assert_eq(reopen(wb).get_cell_value("S", "A1", raw=true), Some("2"))
  assert_eq(cell_format(wb, "A1"), Some("0.00"))
}

///|
test "a style-only override keeps the value the cell already had" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=formatted("0.00"))
  wb.add_override(override_at("A1", style=formatted("0%")))
  assert_eq(reopen(wb).get_cell_value("S", "A1", raw=true), Some("1"))
  assert_eq(cell_format(wb, "A1"), Some("0%"))
}

///|
test "an override may carry both facets at once" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=formatted("0.00"))
  wb.add_override(override_at("A1", value=Number(0.5), style=formatted("0%")))
  assert_eq(reopen(wb).get_cell_value("S", "A1", raw=true), Some("0.5"))
  assert_eq(cell_format(wb, "A1"), Some("0%"))
}

///|
test "an override inside a filled range leaves the rest of it shared" {
  let (wb, sheet) = calculation_sheet()
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", style: None, })
  wb.add_override(override_at("C2", value=Formula(formula="B2", cached=None)))
  let reopened = reopen(wb)
  // The master keeps the range's one stored formula and C3 keeps following it;
  // only the overridden cell drops out of the group and holds its own text.
  assert_eq(reopened.get_cell_formula("S", "C1"), Some("A1*B1"))
  assert_eq(reopened.get_cell_formula("S", "C2"), Some("B2"))
  assert_eq(reopened.get_cell_formula("S", "C3"), None)
  assert_eq(reopened.sheet("S").unwrap().formula_refs(), ["C1", "C2"])
}

///|
test "an override inside a filled range may be a plain value" {
  let (wb, sheet) = calculation_sheet()
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", style: None, })
  wb.add_override(override_at("C2", value=Number(0.0)))
  let reopened = reopen(wb)
  assert_eq(reopened.get_cell_formula("S", "C2"), None)
  assert_eq(reopened.get_cell_value("S", "C2"), Some("0"))
  assert_eq(reopened.get_cell_formula("S", "C1"), Some("A1*B1"))
}

///|
test "a filled range's band style survives an override of one of its cells" {
  let (wb, sheet) = calculation_sheet()
  sheet.set_column_band(first=3, last=3, style=formatted("0.00"))
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1", style: None, })
  wb.add_override(override_at("C2", value=Number(7.0)))
  assert_eq(cell_format(wb, "C2"), Some("0.00"))
}

///|
test "overrides reach only the sheet they name" {
  let wb = @model.Workbook()
  let first = wb.add_sheet("S")
  let second = wb.add_sheet("T")
  first.set(@units.CellRef(col=1, row=1), Text("first"))
  second.set(@units.CellRef(col=1, row=1), Text("second"))
  wb.add_override(override_at("A1", value=Text("by hand")))
  let reopened = reopen(wb)
  assert_eq(reopened.get_cell_value("S", "A1"), Some("by hand"))
  assert_eq(reopened.get_cell_value("T", "A1"), Some("second"))
}

///|
test "a table takes its column name from the override, not what it displaced" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef(col=1, row=1), Text("Region"))
  sheet.set(@units.CellRef(col=1, row=2), Text("APAC"))
  sheet.add_table(plain_table(range("A1", "A2"), name="Sales"))
  wb.add_override(override_at("A1", value=Text("Area")))
  // Excel refuses a table whose column names disagree with its header cells, so
  // the ordering the emitter keeps — overrides after everything that writes a
  // cell, before everything that reads one — is what makes this pair agree.
  assert_eq(reopen(wb).get_cell_value("S", "A1"), Some("Area"))
  assert_eq(only_table(wb).columns, ["Area"])
}

///|
test "a format-only override replaces the cell's own look, band kept" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=1, last=1, style=filled("FFFF00"))
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=bold())
  wb.add_override(override_at("A1", style=formatted("0.0")))
  assert_eq(cell_format(wb, "A1"), Some("0.0"))
  assert_false(cell_is_bold(wb, "A1"))
  assert_eq(cell_fill(wb, "A1"), Some("FFFF00"))
}

///|
test "a style override replaces the cell's own look, band kept" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=1, last=1, style=filled("FFFF00"))
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=bold())
  wb.add_override(
    override_at("A1", style={
      ..@model.Style::empty(),
      font: Some({ ..@model.Font::empty(), italic: Some(true), }),
    }),
  )
  let reopened = reopen(wb)
  let font = reopened.get_style(reopened.get_cell_style("S", "A1").unwrap()).font.unwrap()
  assert_eq(font.bold, None)
  assert_eq(font.italic, Some(true))
  assert_eq(cell_fill(wb, "A1"), Some("FFFF00"))
}

///|
test "a cleared format in an override still clears what the band sets" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=1, last=1, style={
    ..filled("FFFF00"),
    number_format: Some("0.00"),
  })
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=bold())
  wb.add_override(override_at("A1", style=clears([NumberFormat])))
  assert_eq(cell_format(wb, "A1"), None)
  assert_false(cell_is_bold(wb, "A1"))
  assert_eq(cell_fill(wb, "A1"), Some("FFFF00"))
}

///|
test "an override clearing a cell's only style leaves it on the default" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=formatted("0.00"))
  wb.add_override(override_at("A1", style=clears([NumberFormat])))
  assert_eq(reopen(wb).get_cell_style("S", "A1"), Some(0))
}

///|
test "a value-only override keeps both the cell's own look and its band" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=1, last=1, style=filled("FFFF00"))
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=bold())
  wb.add_override(override_at("A1", value=Number(9.0)))
  assert_true(cell_is_bold(wb, "A1"))
  assert_eq(cell_fill(wb, "A1"), Some("FFFF00"))
}

///|
test "an override with both facets keeps the band under its style" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=1, last=1, style=filled("FFFF00"))
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), style=bold())
  wb.add_override(override_at("A1", value=Number(0.5), style=formatted("0%")))
  assert_eq(cell_format(wb, "A1"), Some("0%"))
  assert_false(cell_is_bold(wb, "A1"))
  assert_eq(cell_fill(wb, "A1"), Some("FFFF00"))
}

///|
test "a style override inside a filled range replaces the range's style" {
  let (wb, sheet) = calculation_sheet()
  sheet.set_column_band(first=3, last=3, style=filled("FFFF00"))
  sheet.add_formula({
    at: range_of("C1", "C3"),
    formula: "A1*B1",
    style: Some(bold()),
  })
  wb.add_override(override_at("C2", style=formatted("0.0")))
  assert_eq(cell_format(wb, "C2"), Some("0.0"))
  assert_false(cell_is_bold(wb, "C2"))
  assert_eq(cell_fill(wb, "C2"), Some("FFFF00"))
  assert_true(cell_is_bold(wb, "C3"))
}

///|
test "a text override drops the band's number format, as a text cell does" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=1, last=1, style={
    ..bold(),
    number_format: Some("0.00"),
  })
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0))
  wb.add_override(override_at("A1", value=Text("n/a")))
  assert_eq(cell_format(wb, "A1"), None)
  assert_true(cell_is_bold(wb, "A1"))
}
