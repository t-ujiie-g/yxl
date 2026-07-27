// Round-trip tests for form controls: compile to real bytes, re-open, and
// assert on the controls the sheet carries.

///|
/// The sole form control the round-tripped workbook carries.
fn only_control(wb : @model.Workbook) -> @xlsx.FormControl raise {
  let reopened = reopen(wb)
  let controls = reopened.get_form_controls("S")
  assert_eq(controls.length(), 1)
  controls[0]
}

///|
/// A control with nothing set but its anchor and kind.
fn plain_control(kind : @model.FormControlKind) -> @model.FormControl {
  {
    at: @units.CellRef::parse_a1("B2").unwrap(),
    kind,
    text: None,
    checked: None,
    link: None,
    width: None,
    height: None,
    min: None,
    max: None,
    step: None,
    page: None,
    value: None,
    horizontal: None,
  }
}

///|
test "a check box round-trips its caption, tick, and linked cell" {
  let (wb, sheet) = fixture()
  sheet.add_control({
    ..plain_control(CheckBox),
    text: Some("Include VAT"),
    checked: Some(true),
    link: @units.CellRef::parse_a1("D2"),
  })
  let control = only_control(wb)
  assert_eq(control.control_type, "CheckBox")
  assert_eq(control.cell, "B2")
  assert_eq(control.text, "Include VAT")
  assert_eq(control.checked, Some(true))
  assert_eq(control.cell_link, Some("D2"))
}

///|
test "a scroll bar round-trips its range, step, page, value, and orientation" {
  let (wb, sheet) = fixture()
  sheet.add_control({
    ..plain_control(ScrollBar),
    link: @units.CellRef::parse_a1("D2"),
    min: Some(0),
    max: Some(100),
    step: Some(5),
    page: Some(20),
    value: Some(40),
    horizontal: Some(true),
  })
  let control = only_control(wb)
  assert_eq(control.control_type, "ScrollBar")
  assert_eq(control.min_val, Some(0))
  assert_eq(control.max_val, Some(100))
  assert_eq(control.inc_change, Some(5))
  assert_eq(control.page_change, Some(20))
  assert_eq(control.current_val, Some(40))
  assert_eq(control.horizontally, Some(true))
}

///|
test "every kind round-trips as itself" {
  let kinds : Array[(@model.FormControlKind, String)] = [
    (Button, "Button"),
    (CheckBox, "CheckBox"),
    (OptionButton, "OptionButton"),
    (ScrollBar, "ScrollBar"),
    (SpinButton, "SpinButton"),
    (GroupBox, "GroupBox"),
    (Label, "Label"),
  ]
  for entry in kinds {
    let (kind, expected) = entry
    let (wb, sheet) = fixture()
    // A size is set but not asserted: it lands in the VML anchor, which the
    // backend's reader does not translate back into width/height — the manual
    // Excel check is what sees it.
    sheet.add_control({
      ..plain_control(kind),
      width: Some(140),
      height: Some(28),
    })
    assert_eq(only_control(wb).control_type, expected)
  }
}
