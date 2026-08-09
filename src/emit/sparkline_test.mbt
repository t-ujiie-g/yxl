///|
/// The sole sparkline group the round-tripped workbook carries.
fn only_sparkline_group(wb : @model.Workbook) -> @xlsx.SparklineGroup raise {
  let reopened = reopen(wb)
  guard reopened.sheet("S") is Some(sheet) else { fail("expected the sheet") }
  let groups = sheet.sparkline_groups()
  assert_eq(groups.length(), 1)
  groups[0]
}

///|
/// A group of one line sparkline at F2 over B2:E2, everything else default.
fn line_group() -> @model.SparklineGroup {
  {
    kind: Line,
    cells: [
      {
        at: @units.CellRef::parse_a1("F2").unwrap(),
        data: {
          sheet: None,
          range: {
            top_left: @units.CellRef::parse_a1("B2").unwrap(),
            bottom_right: @units.CellRef::parse_a1("E2").unwrap(),
          },
        },
      },
    ],
    markers: false,
    high: false,
    low: false,
    min: None,
    max: None,
    weight: None,
    color: None,
    markers_color: None,
    high_color: None,
    low_color: None,
    axis: false,
  }
}

///|
test "a sparkline round-trips its location, data, and kind" {
  let (wb, sheet) = fixture()
  sheet.add_sparkline_group({ ..line_group(), kind: WinLoss })
  let group = only_sparkline_group(wb)
  assert_true(group.sparkline_type is WinLoss)
  assert_eq(group.sparklines.length(), 1)
  assert_eq(group.sparklines[0].location, "F2")
  assert_eq(group.sparklines[0].range_ref, "B2:E2")
}

///|
test "a group's emphasis, bounds, weight, colours, and axis survive" {
  let (wb, sheet) = fixture()
  sheet.add_sparkline_group({
    ..line_group(),
    markers: true,
    high: true,
    low: true,
    min: Some(0),
    max: Some(20),
    weight: Some(1.25),
    color: @units.Color::parse("1F77B4"),
    markers_color: @units.Color::parse("333333"),
    high_color: @units.Color::parse("CC0000"),
    low_color: @units.Color::parse("0000CC"),
    axis: true,
  })
  let options = only_sparkline_group(wb).options
  assert_eq(options.markers, true)
  assert_eq(options.high, true)
  assert_eq(options.low, true)
  assert_eq(options.manual_min, Some(0))
  assert_eq(options.manual_max, Some(20))
  assert_eq(options.line_weight, Some(1.25))
  assert_eq(options.display_x_axis, true)
  // The backend stores a colour with its alpha channel in front.
  assert_eq(options.color_series.unwrap().rgb, Some("FF1F77B4"))
  assert_eq(options.color_markers.unwrap().rgb, Some("FF333333"))
  assert_eq(options.color_high.unwrap().rgb, Some("FFCC0000"))
  assert_eq(options.color_low.unwrap().rgb, Some("FF0000CC"))
}

///|
test "a group of several cells lands one sparkline per cell, in order" {
  let (wb, sheet) = fixture()
  let base = line_group()
  sheet.add_sparkline_group({
    ..base,
    kind: Column,
    cells: [
      base.cells[0],
      {
        at: @units.CellRef::parse_a1("F3").unwrap(),
        data: {
          sheet: Some("Data"),
          range: {
            top_left: @units.CellRef::parse_a1("B3").unwrap(),
            bottom_right: @units.CellRef::parse_a1("E3").unwrap(),
          },
        },
      },
    ],
  })
  wb.add_sheet("Data") |> ignore
  let group = only_sparkline_group(wb)
  assert_eq(group.sparklines.length(), 2)
  assert_eq(group.sparklines[0].location, "F2")
  assert_eq(group.sparklines[1].location, "F3")
  // Both read back bare: the backend's reader strips any sheet prefix off the
  // stored reference, the cross-sheet one included. The emitted XML does keep
  // `'Data'!B3:E3` — verified against the written part, since this accessor
  // cannot show it.
  assert_eq(group.sparklines[0].range_ref, "B2:E2")
  assert_eq(group.sparklines[1].range_ref, "B3:E3")
}
