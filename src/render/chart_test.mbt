// Tests for how a chart reads as a spec. What matters here is the *spelling* —
// the keys, their order, and what is left unsaid — since whether the result
// compiles is settled by `cli`'s verify pass. The text is asserted whole,
// because a spec is read whole.

///|
test "a chart renders as its identity, then its trimmings, then its series" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.add_chart({
    at: at("E2"),
    kind: ColumnStacked,
    series: [
      {
        values: {
          sheet: Some("Figures"),
          range: { top_left: at("B2"), bottom_right: at("B4") },
        },
        categories: Some({
          sheet: Some("Figures"),
          range: { top_left: at("A2"), bottom_right: at("A4") },
        }),
        name: Some(FromCell(sheet=Some("Figures"), at=at("B1"))),
      },
      {
        values: {
          sheet: None,
          range: { top_left: at("C2"), bottom_right: at("C4") },
        },
        categories: None,
        name: Some(Literal("Cost")),
      },
    ],
    title: Some("Revenue and cost"),
    legend: Some(Bottom),
    size: Some({ width: 520, height: 300 }),
    x_axis: Some({ title: Some("Region"), min: None, max: None }),
    y_axis: Some({ title: None, min: Some(0.0), max: Some(4000000.0) }),
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: Region
      #|    charts:
      #|      - at: E2
      #|        type: column_stacked
      #|        title: Revenue and cost
      #|        legend: bottom
      #|        size:
      #|          width: 520
      #|          height: 300
      #|        x_axis:
      #|          title: Region
      #|        y_axis:
      #|          min: 0
      #|          max: 4000000
      #|        series:
      #|          - values: Figures!B2:B4
      #|            categories: Figures!A2:A4
      #|            name_from: Figures!B1
      #|          - values: C2:C4
      #|            name: Cost
      #|
    ),
  )
}

///|
test "a chart that asked for nothing extra says nothing extra" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.add_chart({
    at: at("D1"),
    kind: Pie,
    series: [
      {
        values: {
          sheet: None,
          range: { top_left: at("B1"), bottom_right: at("B3") },
        },
        categories: None,
        name: None,
      },
    ],
    title: None,
    legend: None,
    size: None,
    x_axis: None,
    y_axis: None,
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: Region
      #|    charts:
      #|      - at: D1
      #|        type: pie
      #|        series:
      #|          - values: B1:B3
      #|
    ),
  )
}

///|
test "a chart drawn without a legend says so, since unset means something else" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.add_chart({
    at: at("D1"),
    kind: Line,
    series: [
      {
        values: {
          sheet: None,
          range: { top_left: at("B1"), bottom_right: at("B3") },
        },
        categories: None,
        name: None,
      },
    ],
    title: None,
    legend: Some(NoLegend),
    size: None,
    x_axis: None,
    y_axis: None,
  })
  assert_true(spec(wb).contains("legend: none"))
}
