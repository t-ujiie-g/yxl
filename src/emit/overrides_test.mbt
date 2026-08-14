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
  sheet.set(@units.CellRef::new(col=1, row=1), Text("from the template"))
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
  sheet.set(@units.CellRef::new(col=1, row=1), Text("from the template"))
  assert_eq(reopen(wb).get_cell_value("S", "A1"), Some("by hand"))
}

///|
test "a value-only override keeps the style the cell already had" {
  let (wb, sheet) = fixture()
  sheet.set(
    @units.CellRef::new(col=1, row=1),
    Number(1.0),
    style=formatted("0.00"),
  )
  wb.add_override(override_at("A1", value=Number(2.0)))
  assert_eq(reopen(wb).get_cell_value("S", "A1", raw=true), Some("2"))
  assert_eq(cell_format(wb, "A1"), Some("0.00"))
}

///|
test "a style-only override keeps the value the cell already had" {
  let (wb, sheet) = fixture()
  sheet.set(
    @units.CellRef::new(col=1, row=1),
    Number(1.0),
    style=formatted("0.00"),
  )
  wb.add_override(override_at("A1", style=formatted("0%")))
  assert_eq(reopen(wb).get_cell_value("S", "A1", raw=true), Some("1"))
  assert_eq(cell_format(wb, "A1"), Some("0%"))
}

///|
test "an override may carry both facets at once" {
  let (wb, sheet) = fixture()
  sheet.set(
    @units.CellRef::new(col=1, row=1),
    Number(1.0),
    style=formatted("0.00"),
  )
  wb.add_override(override_at("A1", value=Number(0.5), style=formatted("0%")))
  assert_eq(reopen(wb).get_cell_value("S", "A1", raw=true), Some("0.5"))
  assert_eq(cell_format(wb, "A1"), Some("0%"))
}

///|
test "an override inside a filled range leaves the rest of it shared" {
  let (wb, sheet) = calculation_sheet()
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1" })
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
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1" })
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
  sheet.add_formula({ at: range_of("C1", "C3"), formula: "A1*B1" })
  wb.add_override(override_at("C2", value=Number(7.0)))
  assert_eq(cell_format(wb, "C2"), Some("0.00"))
}

///|
test "overrides reach only the sheet they name" {
  let wb = @model.Workbook::new()
  let first = wb.add_sheet("S")
  let second = wb.add_sheet("T")
  first.set(@units.CellRef::new(col=1, row=1), Text("first"))
  second.set(@units.CellRef::new(col=1, row=1), Text("second"))
  wb.add_override(override_at("A1", value=Text("by hand")))
  let reopened = reopen(wb)
  assert_eq(reopened.get_cell_value("S", "A1"), Some("by hand"))
  assert_eq(reopened.get_cell_value("T", "A1"), Some("second"))
}

///|
test "a table takes its column name from the override, not what it displaced" {
  let (wb, sheet) = fixture()
  sheet.set(@units.CellRef::new(col=1, row=1), Text("Region"))
  sheet.set(@units.CellRef::new(col=1, row=2), Text("APAC"))
  sheet.add_table(plain_table(range("A1", "A2"), name="Sales"))
  wb.add_override(override_at("A1", value=Text("Area")))
  // Excel refuses a table whose column names disagree with its header cells, so
  // the ordering the emitter keeps — overrides after everything that writes a
  // cell, before everything that reads one — is what makes this pair agree.
  assert_eq(reopen(wb).get_cell_value("S", "A1"), Some("Area"))
  assert_eq(only_table(wb).columns, ["Area"])
}
