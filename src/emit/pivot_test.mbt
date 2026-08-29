///|
/// A workbook whose `Orders` sheet holds four named columns over two rows, and
/// a `Summary` sheet ready for a pivot over them.
fn source_workbook() -> (@model.Workbook, @model.Sheet) {
  let wb = @model.Workbook::new()
  let summary = wb.add_sheet("S")
  let orders = wb.add_sheet("Orders")
  for column, header in ["Region", "Quarter", "Channel", "Revenue"] {
    orders.set(@units.CellRef::new(col=column + 1, row=1), Text(header))
  }
  for row in 2..<=3 {
    orders.set(@units.CellRef::new(col=1, row~), Text("R\{row}"))
    orders.set(@units.CellRef::new(col=2, row~), Text("Q3"))
    orders.set(@units.CellRef::new(col=3, row~), Text("Direct"))
    orders.set(@units.CellRef::new(col=4, row~), Number(row.to_double()))
  }
  (wb, summary)
}

///|
/// A pivot of revenue by region, over the `Orders` sheet.
fn plain_pivot() -> @model.Pivot {
  {
    at: range("A1", "E20"),
    source: { sheet: Some("Orders"), range: range("A1", "D3"), },
    rows: [{ field: "Region", name: None, }],
    columns: [],
    values: [{ field: "Revenue", function: Sum, name: None, }],
    name: None,
    style: None,
    row_grand_totals: true,
    column_grand_totals: true,
  }
}

///|
/// The sole pivot the round-tripped workbook carries on `S`.
fn only_pivot(wb : @model.Workbook) -> @xlsx.PivotTable raise {
  let reopened = reopen(wb)
  let pivots = reopened.get_pivot_tables("S")
  assert_eq(pivots.length(), 1)
  pivots[0]
}

///|
test "a pivot round-trips as its location, its axes, and its source" {
  let (wb, sheet) = source_workbook()
  sheet.add_pivot(plain_pivot())
  let pivot = only_pivot(wb)
  assert_eq(pivot.name, "PivotTable1")
  assert_true(pivot.table_xml.contains("<location ref=\"A1:E20\""))
  // The field indices are positions in the source's header row: Region is the
  // first column, Revenue the fourth.
  assert_true(
    pivot.table_xml.contains("<pivotField name=\"Region\" axis=\"axisRow\""),
  )
  assert_true(pivot.table_xml.contains("<dataField fld=\"3\""))
  // The cache names the source without quoting the sheet, and asks Excel to
  // refresh on open — the file carries no summary of its own.
  assert_true(
    pivot.cache_definition_xml.contains(
      "<worksheetSource ref=\"A1:D3\" sheet=\"Orders\"/>",
    ),
  )
  assert_true(pivot.cache_definition_xml.contains("refreshOnLoad=\"1\""))
}

///|
test "each axis puts its fields where Excel expects them" {
  let (wb, sheet) = source_workbook()
  sheet.add_pivot({
    ..plain_pivot(),
    rows: [{ field: "Region", name: None, }, { field: "Channel", name: None, }],
    columns: [{ field: "Quarter", name: Some("Period"), }],
  })
  let xml = only_pivot(wb).table_xml
  assert_true(xml.contains("<pivotField name=\"Region\" axis=\"axisRow\""))
  assert_true(xml.contains("<pivotField name=\"Channel\" axis=\"axisRow\""))
  assert_true(xml.contains("<pivotField name=\"Period\" axis=\"axisCol\""))
  assert_true(xml.contains("<field x=\"1\"/>"))
}

///|
test "every aggregation reaches the file under its OOXML name" {
  let expected : Array[(@model.PivotFunction, String)] = [
    (Sum, "sum"),
    (Count, "count"),
    (CountNumbers, "countNums"),
    (Average, "average"),
    (Max, "max"),
    (Min, "min"),
    (Product, "product"),
    (StdDev, "stdDev"),
    (StdDevP, "stdDevp"),
    (Var, "var"),
    (VarP, "varp"),
  ]
  for entry in expected {
    let (function, name) = entry
    let (wb, sheet) = source_workbook()
    sheet.add_pivot({
      ..plain_pivot(),
      values: [{ field: "Revenue", function, name: None, }],
    })
    assert_true(only_pivot(wb).table_xml.contains("subtotal=\"\{name}\""))
  }
}

///|
test "a named pivot, field, and style reach the file" {
  let (wb, sheet) = source_workbook()
  sheet.add_pivot({
    ..plain_pivot(),
    name: Some("RevenueByRegion"),
    style: Some("PivotStyleMedium9"),
    values: [{ field: "Revenue", function: Sum, name: Some("Total revenue"), }],
  })
  let pivot = only_pivot(wb)
  assert_eq(pivot.name, "RevenueByRegion")
  assert_true(pivot.table_xml.contains("name=\"Total revenue\""))
  assert_true(
    pivot.table_xml.contains("<pivotTableStyleInfo name=\"PivotStyleMedium9\""),
  )
}

///|
test "grand totals are on unless the spec turns them off" {
  let (wb, sheet) = source_workbook()
  sheet.add_pivot(plain_pivot())
  let on = only_pivot(wb).table_xml
  assert_true(on.contains("rowGrandTotals=\"1\""))
  assert_true(on.contains("colGrandTotals=\"1\""))
  let (wb, sheet) = source_workbook()
  sheet.add_pivot({
    ..plain_pivot(),
    row_grand_totals: false,
    column_grand_totals: false,
  })
  let off = only_pivot(wb).table_xml
  assert_true(off.contains("rowGrandTotals=\"0\""))
  assert_true(off.contains("colGrandTotals=\"0\""))
}

///|
test "a pivot may summarize the sheet it sits on" {
  let (wb, sheet) = source_workbook()
  for column, header in ["Region", "Revenue"] {
    sheet.set(@units.CellRef::new(col=column + 1, row=1), Text(header))
  }
  sheet.set(@units.CellRef::new(col=1, row=2), Text("APAC"))
  sheet.set(@units.CellRef::new(col=2, row=2), Number(1.0))
  sheet.add_pivot({
    ..plain_pivot(),
    at: range("D1", "F20"),
    source: { sheet: None, range: range("A1", "B2"), },
  })
  assert_true(only_pivot(wb).cache_definition_xml.contains("sheet=\"S\""))
}
