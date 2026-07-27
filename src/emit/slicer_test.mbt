// Round-trip tests for slicers: compile to real bytes, re-open, and assert on
// the panel the sheet carries.

///|
/// A sheet with a named three-column table for a slicer to filter.
fn table_fixture(sheet : @model.Sheet, name : String) -> Unit {
  for col, header in ["Region", "Type", "Sales"] {
    sheet.set(@units.CellRef::new(col=col + 1, row=1), Text(header))
  }
  sheet.set(@units.CellRef::new(col=1, row=2), Text("APAC"))
  sheet.set(@units.CellRef::new(col=2, row=2), Text("Direct"))
  sheet.set(@units.CellRef::new(col=3, row=2), Number(2400.0))
  sheet.add_table({
    at: {
      top_left: @units.CellRef::new(col=1, row=1),
      bottom_right: @units.CellRef::new(col=3, row=4),
    },
    name: Some(name),
    style: None,
    banded_rows: true,
    banded_columns: false,
    first_column: false,
    last_column: false,
  })
}

///|
test "a slicer round-trips its column, anchor, table, and looks" {
  let (wb, sheet) = fixture()
  table_fixture(sheet, "Sales")
  sheet.add_slicer({
    at: @units.CellRef::parse_a1("E1").unwrap(),
    table: "Sales",
    column: "Region",
    caption: Some("Pick a region"),
    width: Some(240),
    height: Some(180),
    header: Some(false),
  })
  let reopened = reopen(wb)
  let slicers = reopened.get_slicers("S")
  assert_eq(slicers.length(), 1)
  assert_eq(slicers[0].name, "Region")
  assert_eq(slicers[0].source_name, "Region")
  assert_eq(slicers[0].cell, "E1")
  assert_eq(slicers[0].table_sheet, "S")
  assert_eq(slicers[0].table_name, "Sales")
  assert_eq(slicers[0].caption, "Pick a region")
  assert_eq(slicers[0].width, 240)
  assert_eq(slicers[0].height, 180)
  assert_eq(slicers[0].display_header, Some(false))
}

///|
test "a slicer may sit on one sheet and filter a table on another" {
  let (wb, dashboard) = fixture()
  let data = wb.add_sheet("Data")
  table_fixture(data, "Orders")
  dashboard.add_slicer({
    at: @units.CellRef::parse_a1("B2").unwrap(),
    table: "Orders",
    column: "Type",
    caption: None,
    width: None,
    height: None,
    header: None,
  })
  let reopened = reopen(wb)
  let slicers = reopened.get_slicers("S")
  assert_eq(slicers.length(), 1)
  assert_eq(slicers[0].name, "Type")
  // The emitter resolved the table's own sheet, not the slicer's.
  assert_eq(slicers[0].table_sheet, "Data")
  assert_eq(slicers[0].table_name, "Orders")
}
