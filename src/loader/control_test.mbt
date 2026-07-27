// Schema tests for a sheet's `controls:`.

///|
/// The sole control a spec loads.
fn loaded_control(body : String) -> @model.FormControl raise {
  let controls = load_ok(sheet_spec("    controls:\n" + body)).sheets[0].controls
  assert_eq(controls.length(), 1)
  controls[0]
}

///|
test "a control loads its anchor and kind, leaving the rest unset" {
  let control = loaded_control("      - at: B2\n        kind: button\n")
  assert_eq(control.at.to_a1(), "B2")
  assert_eq(control.kind, Button)
  assert_eq(control.text, None)
  assert_eq(control.checked, None)
  assert_eq(control.link, None)
  assert_eq(control.width, None)
  assert_eq(control.height, None)
  assert_eq(control.min, None)
  assert_eq(control.max, None)
  assert_eq(control.step, None)
  assert_eq(control.page, None)
  assert_eq(control.value, None)
  assert_eq(control.horizontal, None)
}

///|
test "a check box loads its caption, tick, link, and size" {
  let control = loaded_control(
    (
      #|      - at: B2
      #|        kind: check_box
      #|        text: Include VAT
      #|        checked: true
      #|        link: D2
      #|        size: { width: 120, height: 24 }
      #|
    ),
  )
  assert_eq(control.kind, CheckBox)
  assert_eq(control.text, Some("Include VAT"))
  assert_eq(control.checked, Some(true))
  assert_eq(control.link.unwrap().to_a1(), "D2")
  assert_eq(control.width, Some(120))
  assert_eq(control.height, Some(24))
}

///|
test "a scroll bar loads its range, step, page, value, and orientation" {
  let control = loaded_control(
    (
      #|      - at: B2
      #|        kind: scroll_bar
      #|        link: D2
      #|        min: 0
      #|        max: 100
      #|        step: 5
      #|        page: 20
      #|        value: 40
      #|        horizontal: true
      #|
    ),
  )
  assert_eq(control.kind, ScrollBar)
  assert_eq(control.min, Some(0))
  assert_eq(control.max, Some(100))
  assert_eq(control.step, Some(5))
  assert_eq(control.page, Some(20))
  assert_eq(control.value, Some(40))
  assert_eq(control.horizontal, Some(true))
}

///|
test "a control needs its anchor and its kind, and kinds are named" {
  assert_eq(
    schema_message(sheet_spec("    controls:\n      - kind: button\n")),
    Some("spec.yaml: a control is missing required key 'at'"),
  )
  assert_eq(
    schema_message(sheet_spec("    controls:\n      - at: B2\n")),
    Some("spec.yaml: control at 'B2' is missing required key 'kind'"),
  )
  guard schema_message(
      sheet_spec("    controls:\n      - at: B2\n        kind: dial\n"),
    )
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_eq(
    message, "spec.yaml: unknown control kind 'dial' in control at 'B2' (expected 'button', 'check_box', 'option_button', 'scroll_bar', 'spin_button', 'group_box', or 'label')",
  )
}

///|
test "each key is refused on a kind whose dialog does not show it" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: spin_button\n        text: Up\n",
      ),
    ),
    Some(
      "spec.yaml: control at 'B2' sets 'text', which belongs to a control that carries a caption (this one is 'spin_button')",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: button\n        checked: true\n",
      ),
    ),
    Some(
      "spec.yaml: control at 'B2' sets 'checked', which belongs to a 'check_box' or 'option_button' (this one is 'button')",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: label\n        link: D2\n",
      ),
    ),
    Some(
      "spec.yaml: control at 'B2' sets 'link', which belongs to a control that writes a value ('check_box', 'option_button', 'scroll_bar', or 'spin_button') (this one is 'label')",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: check_box\n        min: 1\n",
      ),
    ),
    Some(
      "spec.yaml: control at 'B2' sets 'min', which belongs to a 'scroll_bar' or 'spin_button' (this one is 'check_box')",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: spin_button\n        page: 10\n",
      ),
    ),
    Some(
      "spec.yaml: control at 'B2' sets 'page', which belongs to a 'scroll_bar' (a spin button has no trough) (this one is 'spin_button')",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: group_box\n        horizontal: true\n",
      ),
    ),
    Some(
      "spec.yaml: control at 'B2' sets 'horizontal', which belongs to a 'scroll_bar' or 'spin_button' (this one is 'group_box')",
    ),
  )
}

///|
test "control values stay within Excel's dialog limits, in order" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: spin_button\n        max: 30001\n",
      ),
    ),
    Some(
      "spec.yaml: control at 'B2' 'max' must be a whole number between 0 and 30000",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: spin_button\n        value: -1\n",
      ),
    ),
    Some(
      "spec.yaml: control at 'B2' 'value' must be a whole number between 0 and 30000",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: scroll_bar\n        min: 50\n        max: 10\n",
      ),
    ),
    Some("spec.yaml: control at 'B2' has 'min' 50 above 'max' 10"),
  )
}

///|
test "a control rejects an unknown key" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    controls:\n      - at: B2\n        kind: button\n        macro: Beep\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'macro' in control at 'B2' (expected 'at', 'kind', 'text', 'checked', 'link', 'size', 'min', 'max', 'step', 'page', 'value', or 'horizontal')",
    ),
  )
}
