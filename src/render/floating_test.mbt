///|
test "a shape renders as its geometry, then how it looks" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_shape({
    at: at("D1"),
    preset: "cloud",
    text: Some(Plain("Approved")),
    width: Some(220),
    height: Some(110),
    fill: @units.Color::parse("D6E9F8"),
    line_color: @units.Color::parse("1F77B4"),
    line_width: Some(2.0),
    alt_text: Some("An approval stamp"),
    positioning: Fixed,
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: x
      #|    shapes:
      #|      - at: D1
      #|        kind: cloud
      #|        text: Approved
      #|        size:
      #|          width: 220
      #|          height: 110
      #|        fill: D6E9F8
      #|        line:
      #|          color: "1F77B4"
      #|          width: 2
      #|        alt: An approval stamp
      #|        positioning: fixed
      #|
    ),
  )
}

///|
test "a shape outline without a width renders as a bare colour" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_shape({
    at: at("D1"),
    preset: "plus",
    text: Some(
      Lines([{ text: "one", font: None }, { text: "two", font: None }]),
    ),
    width: None,
    height: None,
    fill: None,
    line_color: @units.Color::parse("1F77B4"),
    line_width: None,
    alt_text: None,
    positioning: Move,
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: x
      #|    shapes:
      #|      - at: D1
      #|        kind: plus
      #|        text:
      #|          - one
      #|          - two
      #|        line: "1F77B4"
      #|
    ),
  )
}

///|
test "one sparkline is placed the short way, several the long way" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  let range = @model.CellRange::parse("B1:B3").unwrap()
  sheet.add_sparkline_group({
    kind: Line,
    cells: [{ at: at("C1"), data: { sheet: None, range } }],
    markers: true,
    high: true,
    low: false,
    min: None,
    max: None,
    weight: Some(2.25),
    color: @units.Color::parse("1F77B4"),
    markers_color: None,
    high_color: @units.Color::parse("CC0000"),
    low_color: None,
    axis: false,
  })
  sheet.add_sparkline_group({
    kind: WinLoss,
    cells: [
      { at: at("D1"), data: { sheet: Some("Results"), range } },
      { at: at("D2"), data: { sheet: None, range } },
    ],
    markers: false,
    high: false,
    low: false,
    min: Some(0),
    max: Some(10),
    weight: None,
    color: None,
    markers_color: None,
    high_color: None,
    low_color: None,
    axis: true,
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: x
      #|    sparklines:
      #|      - at: C1
      #|        data: B1:B3
      #|        markers: true
      #|        high: true
      #|        weight: 2.25
      #|        color: "1F77B4"
      #|        colors:
      #|          high: CC0000
      #|      - cells:
      #|          - at: D1
      #|            data: Results!B1:B3
      #|          - at: D2
      #|            data: B1:B3
      #|        type: win_loss
      #|        min: 0
      #|        max: 10
      #|        axis: true
      #|
    ),
  )
}

///|
test "a control renders only the keys its kind carries" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.add_control({
    at: at("F2"),
    kind: CheckBox,
    text: Some("Rush order"),
    checked: Some(true),
    link: Some(at("G2")),
    width: Some(110),
    height: Some(20),
    min: None,
    max: None,
    step: None,
    page: None,
    value: None,
    horizontal: None,
  })
  sheet.add_control({
    at: at("F4"),
    kind: SpinButton,
    text: None,
    checked: None,
    link: Some(at("H4")),
    width: None,
    height: None,
    min: Some(1),
    max: Some(5),
    step: Some(1),
    page: None,
    value: Some(3),
    horizontal: Some(true),
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: x
      #|    controls:
      #|      - at: F2
      #|        kind: check_box
      #|        text: Rush order
      #|        checked: true
      #|        link: G2
      #|        size:
      #|          width: 110
      #|          height: 20
      #|      - at: F4
      #|        kind: spin_button
      #|        link: H4
      #|        min: 1
      #|        max: 5
      #|        step: 1
      #|        value: 3
      #|        horizontal: true
      #|
    ),
  )
}

///|
test "a slicer renders the table column it filters" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.add_table({
    at: @model.CellRange::parse("A1:A2").unwrap(),
    name: Some("Revenue"),
    style: None,
    banded_rows: true,
    banded_columns: false,
    first_column: false,
    last_column: false,
  })
  sheet.add_slicer({
    at: at("G1"),
    table: "Revenue",
    column: "Region",
    caption: Some("Filter by region"),
    width: Some(160),
    height: Some(140),
    header: None,
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: Region
      #|    tables:
      #|      - at: A1:A2
      #|        name: Revenue
      #|    slicers:
      #|      - at: G1
      #|        table: Revenue
      #|        column: Region
      #|        caption: Filter by region
      #|        size:
      #|          width: 160
      #|          height: 140
      #|
    ),
  )
}
