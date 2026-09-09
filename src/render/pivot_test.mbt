///|
test "a pivot renders its axes, and only the totals it turns off" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_pivot({
    at: @model.CellRange::parse("A3:F30").unwrap(),
    source: {
      sheet: Some("Orders"),
      range: @model.CellRange::parse("A1:D7").unwrap(),
    },
    rows: [{ field: "Region", name: None, }],
    columns: [{ field: "Quarter", name: Some("Period"), }],
    filters: [{ field: "Channel", name: None, }],
    values: [
      { field: "Revenue", function: Sum, name: None, },
      { field: "Revenue", function: Average, name: Some("Mean"), },
    ],
    name: Some("ByRegion"),
    style: Some("PivotStyleMedium9"),
    row_grand_totals: true,
    column_grand_totals: false,
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: x
      #|    pivots:
      #|      - at: A3:F30
      #|        source: Orders!A1:D7
      #|        name: ByRegion
      #|        rows:
      #|          - Region
      #|        columns:
      #|          - field: Quarter
      #|            name: Period
      #|        filters:
      #|          - Channel
      #|        values:
      #|          - Revenue
      #|          - field: Revenue
      #|            function: average
      #|            name: Mean
      #|        style: PivotStyleMedium9
      #|        column_grand_totals: false
      #|
    ),
  )
}
