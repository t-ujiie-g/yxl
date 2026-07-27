// Loading a sheet's `controls:` — a button, check box, or slider over the
// grid. Each kind takes its own subset of the keys, exactly the combinations
// Excel's "Format Control" dialog offers; anything else is a diagnostic
// naming what the key actually belongs to (ADR-006).

///|
/// The seven kinds, as Excel's Forms toolbar names them. One table serves
/// both the lookup and the diagnostic.
let form_control_kinds : Array[(String, @model.FormControlKind)] = [
  ("button", Button),
  ("check_box", CheckBox),
  ("option_button", OptionButton),
  ("scroll_bar", ScrollBar),
  ("spin_button", SpinButton),
  ("group_box", GroupBox),
  ("label", Label),
]

///|
/// A sheet's `controls:` — a sequence of form controls.
fn load_controls(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'controls'") {
    sheet.add_control(load_control(item, file~))
  }
}

///|
/// One `controls:` entry: where it sits, which control it is, and what the
/// kind's own dialog would let you set on it.
fn load_control(
  node : @yaml.Node,
  file~ : String,
) -> @model.FormControl raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a control")
  guard find_key(entries, "at") is Some(at_node) else {
    raise schema_error(file~, "a control is missing required key 'at'")
  }
  let at = expect_cell_ref(
    expect_string(at_node, file~, context="control 'at'"),
    file~,
    what="control 'at'",
  )
  let context = "control at '\{at.to_a1()}'"
  let mut kind = None
  let mut kind_written = ""
  let mut text = None
  let mut checked = None
  let mut link = None
  let mut width = None
  let mut height = None
  let mut min = None
  let mut max = None
  let mut step = None
  let mut page = None
  let mut value = None
  let mut horizontal = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "at" => () // consumed above
      "kind" => {
        kind_written = expect_string(node, file~, context="\{context} 'kind'")
        kind = Some(
          named(
            form_control_kinds,
            kind_written,
            file~,
            what="control kind",
            context~,
          ),
        )
      }
      "text" =>
        text = Some(expect_string(node, file~, context="\{context} 'text'"))
      "checked" =>
        checked = Some(expect_bool(node, file~, context="\{context} 'checked'"))
      "link" =>
        link = Some(
          expect_cell_ref(
            expect_string(node, file~, context="\{context} 'link'"),
            file~,
            what="\{context} 'link'",
          ),
        )
      "size" => {
        let (w, h) = load_shape_size(node, file~, context~)
        width = Some(w)
        height = Some(h)
      }
      "min" =>
        min = Some(expect_control_value(node, file~, what="\{context} 'min'"))
      "max" =>
        max = Some(expect_control_value(node, file~, what="\{context} 'max'"))
      "step" =>
        step = Some(expect_control_value(node, file~, what="\{context} 'step'"))
      "page" =>
        page = Some(expect_control_value(node, file~, what="\{context} 'page'"))
      "value" =>
        value = Some(
          expect_control_value(node, file~, what="\{context} 'value'"),
        )
      "horizontal" =>
        horizontal = Some(
          expect_bool(node, file~, context="\{context} 'horizontal'"),
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'kind', 'text', 'checked', 'link', 'size', 'min', 'max', 'step', 'page', 'value', or 'horizontal')",
        )
    }
  }
  guard kind is Some(kind) else {
    raise schema_error(file~, "\{context} is missing required key 'kind'")
  }
  // Each key only means something on the kinds whose dialog shows it.
  fn refuse(key : String, belongs : String) -> @diag.SchemaError {
    schema_error(
      file~,
      "\{context} sets '\{key}', which belongs to \{belongs} (this one is '\{kind_written}')",
    )
  }

  if text is Some(_) && kind is (ScrollBar | SpinButton) {
    raise refuse("text", "a control that carries a caption")
  }
  if checked is Some(_) && !(kind is (CheckBox | OptionButton)) {
    raise refuse("checked", "a 'check_box' or 'option_button'")
  }
  if link is Some(_) &&
    !(kind is (CheckBox | OptionButton | ScrollBar | SpinButton)) {
    raise refuse(
      "link", "a control that writes a value ('check_box', 'option_button', 'scroll_bar', or 'spin_button')",
    )
  }
  for ranged in [("min", min), ("max", max), ("step", step), ("value", value)] {
    let (key, set) = ranged
    if set is Some(_) && !(kind is (ScrollBar | SpinButton)) {
      raise refuse(key, "a 'scroll_bar' or 'spin_button'")
    }
  }
  if page is Some(_) && !(kind is ScrollBar) {
    raise refuse("page", "a 'scroll_bar' (a spin button has no trough)")
  }
  if horizontal is Some(_) && !(kind is (ScrollBar | SpinButton)) {
    raise refuse("horizontal", "a 'scroll_bar' or 'spin_button'")
  }
  if min is Some(min) && max is Some(max) && min > max {
    raise schema_error(file~, "\{context} has 'min' \{min} above 'max' \{max}")
  }
  {
    at,
    kind,
    text,
    checked,
    link,
    width,
    height,
    min,
    max,
    step,
    page,
    value,
    horizontal,
  }
}

///|
/// A control's value, bound, step, or page: a whole number within the range
/// Excel's own dialog enforces.
fn expect_control_value(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> Int raise @diag.SchemaError {
  guard node is @yaml.Int(number) &&
    number >= 0L &&
    number <= @model.max_form_control_value.to_int64() else {
    raise schema_error(
      file~,
      "\{what} must be a whole number between 0 and \{@model.max_form_control_value}",
    )
  }
  number.to_int()
}
