///|
/// A workbook whose `Orders` sheet holds four named columns over two rows, and
/// a `Summary` sheet ready for a pivot over them.
fn pivot_fixture() -> (@model.Workbook, @model.Sheet) {
  let wb = @model.Workbook()
  let summary = wb.add_sheet("Summary")
  let orders = wb.add_sheet("Orders")
  for column, header in ["Region", "Quarter", "Channel", "Revenue"] {
    orders.set(@units.CellRef(col=column + 1, row=1), Text(header))
  }
  for row in 2..<=3 {
    orders.set(@units.CellRef(col=1, row~), Text("R\{row}"))
    orders.set(@units.CellRef(col=2, row~), Text("Q3"))
    orders.set(@units.CellRef(col=3, row~), Text("Direct"))
    orders.set(@units.CellRef(col=4, row~), Number(row.to_double()))
  }
  (wb, summary)
}

///|
/// A pivot of revenue by region, over the `Orders` sheet.
fn plain_pivot() -> @model.Pivot {
  {
    at: @model.CellRange::parse("A1:E20").unwrap(),
    source: {
      sheet: Some("Orders"),
      range: @model.CellRange::parse("A1:D3").unwrap(),
    },
    rows: [{ field: "Region", name: None, }],
    columns: [],
    filters: [],
    values: [{ field: "Revenue", function: Sum, name: None, }],
    name: None,
    style: None,
    row_grand_totals: true,
    column_grand_totals: true,
  }
}

///|
/// The sole pivot on the round-tripped `Summary` sheet.
fn only_pivot(wb : @model.Workbook) -> @model.Pivot raise {
  let recovered = round_trip(wb)
  let pivots = recovered.workbook.sheets[0].pivots
  assert_eq(pivots.length(), 1)
  pivots[0]
}

///|
test "a pivot comes back as its location, source, and axes" {
  let (wb, sheet) = pivot_fixture()
  sheet.add_pivot({
    ..plain_pivot(),
    columns: [{ field: "Quarter", name: Some("Period"), }],
    filters: [{ field: "Channel", name: None, }],
  })
  let pivot = only_pivot(wb)
  assert_eq(pivot.at.to_a1(), "A1:E20")
  assert_eq(pivot.source.sheet, Some("Orders"))
  assert_eq(pivot.source.range.to_a1(), "A1:D3")
  assert_eq(pivot.rows, [{ field: "Region", name: None, }])
  assert_eq(pivot.columns, [{ field: "Quarter", name: Some("Period"), }])
  assert_eq(pivot.filters, [{ field: "Channel", name: None, }])
  assert_eq(pivot.values, [{ field: "Revenue", function: Sum, name: None, }])
}

///|
test "a value's own name comes back, and one that repeats the field does not" {
  let (wb, sheet) = pivot_fixture()
  sheet.add_pivot({
    ..plain_pivot(),
    values: [
      { field: "Revenue", function: Average, name: Some("Mean take"), },
      { field: "Revenue", function: Count, name: Some("Revenue"), },
    ],
  })
  let pivot = only_pivot(wb)
  assert_eq(pivot.values[0], {
    field: "Revenue",
    function: Average,
    name: Some("Mean take"),
  })
  // The backend fills an unnamed data field in with the field's own name, so a
  // name that merely repeats it says nothing the spec would have to write.
  assert_eq(pivot.values[1], { field: "Revenue", function: Count, name: None, })
}

///|
test "every aggregation survives the round trip" {
  let functions : Array[@model.PivotFunction] = [
    Sum,
    Count,
    CountNumbers,
    Average,
    Max,
    Min,
    Product,
    StdDev,
    StdDevP,
    Var,
    VarP,
  ]
  let (wb, sheet) = pivot_fixture()
  sheet.add_pivot({
    ..plain_pivot(),
    values: functions.map(function => {
      field: "Revenue",
      function,
      name: None,
    }),
  })
  assert_eq(only_pivot(wb).values.map(value => value.function), functions)
}

///|
test "a pivot's name, style, and grand totals come back" {
  let (wb, sheet) = pivot_fixture()
  sheet.add_pivot({
    ..plain_pivot(),
    name: Some("RevenueByRegion"),
    style: Some("PivotStyleMedium9"),
    row_grand_totals: false,
    column_grand_totals: false,
  })
  let pivot = only_pivot(wb)
  assert_eq(pivot.name, Some("RevenueByRegion"))
  assert_eq(pivot.style, Some("PivotStyleMedium9"))
  assert_false(pivot.row_grand_totals)
  assert_false(pivot.column_grand_totals)
}

///|
test "two pivots over two sources come back as two" {
  let (wb, summary) = pivot_fixture()
  let costs = wb.add_sheet("Costs")
  for column, header in ["Team", "Spend"] {
    costs.set(@units.CellRef(col=column + 1, row=1), Text(header))
  }
  costs.set(@units.CellRef(col=1, row=2), Text("Ops"))
  costs.set(@units.CellRef(col=2, row=2), Number(7.0))
  summary.add_pivot(plain_pivot())
  summary.add_pivot({
    ..plain_pivot(),
    at: @model.CellRange::parse("A30:E50").unwrap(),
    source: {
      sheet: Some("Costs"),
      range: @model.CellRange::parse("A1:B2").unwrap(),
    },
    rows: [{ field: "Team", name: None, }],
    values: [{ field: "Spend", function: Sum, name: None, }],
  })
  let pivots = round_trip(wb).workbook.sheets[0].pivots
  assert_eq(pivots.length(), 2)
  assert_eq(pivots[0].source.sheet, Some("Orders"))
  assert_eq(pivots[1].source.sheet, Some("Costs"))
  assert_eq(pivots[1].rows, [{ field: "Team", name: None, }])
}

///|
test "a recovered pivot compiles back to the same file" {
  let (wb, sheet) = pivot_fixture()
  sheet.add_pivot({
    ..plain_pivot(),
    columns: [{ field: "Quarter", name: Some("Period"), }],
    filters: [{ field: "Channel", name: None, }],
    name: Some("ByRegion"),
    style: Some("PivotStyleDark4"),
  })
  let once = @emit.to_bytes(wb)
  let twice = @emit.to_bytes(@read.from_bytes(once).workbook)
  assert_eq(once, twice)
}
