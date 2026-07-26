// Round-trip tests for Excel tables: each compiles to real `.xlsx` bytes and is
// read back with the backend's reader, so what is asserted is what Excel would
// find in the file.

///|
/// A sheet holding a three-column header row over two rows of data, ready to be
/// declared a table.
fn tabular() -> (@model.Workbook, @model.Sheet) {
  let (wb, sheet) = fixture()
  for column, header in ["Region", "Amount", "Share"] {
    sheet.set(@units.CellRef::new(col=column + 1, row=1), Text(header))
  }
  for row in 2..<=3 {
    sheet.set(@units.CellRef::new(col=1, row~), Text("R\{row}"))
    sheet.set(@units.CellRef::new(col=2, row~), Number(row.to_double()))
    sheet.set(@units.CellRef::new(col=3, row~), Number(0.5))
  }
  (wb, sheet)
}

///|
/// A table as Excel's own "Format as Table" would make it, over `at`.
fn plain_table(at : @model.CellRange, name? : String) -> @model.Table {
  {
    at,
    name,
    style: None,
    banded_rows: true,
    banded_columns: false,
    first_column: false,
    last_column: false,
  }
}

///|
/// The sole table the round-tripped workbook carries.
fn only_table(wb : @model.Workbook) -> @xlsx.Table raise {
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  let tables = reopened.get_tables("S")
  assert_eq(tables.length(), 1)
  tables[0]
}

///|
test "a table round-trips as its range, named by its header row" {
  let (wb, sheet) = tabular()
  sheet.add_table(plain_table(range("A1", "C3"), name="Sales"))
  let table = only_table(wb)
  assert_eq(table.range_ref, "A1:C3")
  assert_eq(table.name, "Sales")
  // The name a formula writes (`Sales[Amount]`) and the one Excel shows are the
  // same thing for a table the spec named.
  assert_eq(table.display_name, "Sales")
  assert_eq(table.columns, ["Region", "Amount", "Share"])
  assert_true(table.show_header_row)
}

///|
test "an unnamed table is named by Excel, not left blank" {
  let (wb, sheet) = tabular()
  sheet.add_table(plain_table(range("A1", "C3")))
  assert_eq(only_table(wb).name, "Table1")
}

///|
test "the appearance toggles reach the file one for one" {
  let (wb, sheet) = tabular()
  sheet.add_table({
    at: range("A1", "C3"),
    name: Some("Sales"),
    style: Some("TableStyleDark3"),
    banded_rows: false,
    banded_columns: true,
    first_column: true,
    last_column: true,
  })
  let table = only_table(wb)
  assert_eq(table.style_name, "TableStyleDark3")
  assert_false(table.show_row_stripes)
  assert_true(table.show_column_stripes)
  assert_true(table.show_first_column)
  assert_true(table.show_last_column)
}

///|
test "a table left unstyled keeps Excel's default banding" {
  let (wb, sheet) = tabular()
  sheet.add_table(plain_table(range("A1", "C3"), name="Sales"))
  let table = only_table(wb)
  assert_eq(table.style_name, "TableStyleMedium9")
  assert_true(table.show_row_stripes)
  assert_false(table.show_column_stripes)
}

///|
test "two tables on one sheet keep their own ranges and names" {
  let (wb, sheet) = tabular()
  sheet.set(@units.CellRef::new(col=5, row=1), Text("Quarter"))
  sheet.set(@units.CellRef::new(col=5, row=2), Text("Q3"))
  sheet.add_table(plain_table(range("A1", "C3"), name="Sales"))
  sheet.add_table(plain_table(range("E1", "E2"), name="Quarters"))
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  let tables = reopened.get_tables("S")
  assert_eq(tables.length(), 2)
  assert_eq(tables[0].name, "Sales")
  assert_eq(tables[0].range_ref, "A1:C3")
  assert_eq(tables[1].name, "Quarters")
  assert_eq(tables[1].range_ref, "E1:E2")
}
