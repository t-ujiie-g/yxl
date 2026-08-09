///|
/// Place a form control on a sheet.
fn apply_control(
  backend : @xlsx.Workbook,
  sheet_name : String,
  control : @model.FormControl,
) -> Unit raise {
  let form = @xlsx.FormControl::new(
    control.at.to_a1(),
    match control.kind {
      Button => "button"
      CheckBox => "check_box"
      OptionButton => "option_button"
      ScrollBar => "scroll_bar"
      SpinButton => "spin_button"
      GroupBox => "group_box"
      Label => "label"
    },
    text?=control.text,
  )
  if control.checked is Some(checked) {
    form.set_checked(checked)
  }
  if control.link is Some(link) {
    form.set_cell_link(link.to_a1())
  }
  if control.width is Some(width) {
    form.set_width(width)
  }
  if control.height is Some(height) {
    form.set_height(height)
  }
  if control.min is Some(min) {
    form.set_min_val(min)
  }
  if control.max is Some(max) {
    form.set_max_val(max)
  }
  if control.step is Some(step) {
    form.set_inc_change(step)
  }
  if control.page is Some(page) {
    form.set_page_change(page)
  }
  if control.value is Some(value) {
    form.set_current_val(value)
  }
  if control.horizontal is Some(horizontal) {
    form.set_horizontally(horizontal)
  }
  backend.add_form_control(sheet_name, form)
}
