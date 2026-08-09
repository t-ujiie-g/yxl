///|
/// A form control anchored at a cell. Which fields mean anything depends on
/// the kind — the loader admits only the combinations Excel's own "Format
/// Control" dialog offers.
///
/// `link` is the cell the control writes its value into: a boolean for a check
/// box, the option's index for an option button, the number for a scroll bar or
/// spin button. Same-sheet only, since the backend refuses a qualified
/// reference. `min`/`max`/`step`/`page`/`value` are a scroll bar's or spin
/// button's range, and all lie within `0..=max_form_control_value`; `page` (a
/// click in the trough) is the scroll bar's alone. `width`/`height` are pixels,
/// `horizontal` lays a scroll bar or spin button sideways, and `None` anywhere
/// keeps the backend's default.
pub(all) struct FormControl {
  at : @units.CellRef
  kind : FormControlKind
  text : String?
  checked : Bool?
  link : @units.CellRef?
  width : Int?
  height : Int?
  min : Int?
  max : Int?
  step : Int?
  page : Int?
  value : Int?
  horizontal : Bool?
} derive(Eq, Debug)

///|
/// The seven controls Excel's Forms toolbar offers (list and combo boxes are
/// the backend's to grow).
pub(all) enum FormControlKind {
  Button
  CheckBox
  OptionButton
  ScrollBar
  SpinButton
  GroupBox
  Label
} derive(Eq, Debug)

///|
/// The largest value, bound, step, or page a control accepts — the limit
/// Excel's own "Format Control" dialog enforces.
pub let max_form_control_value : Int = 30000

///|
/// Place a form control on the sheet.
pub fn Sheet::add_control(self : Sheet, control : FormControl) -> Unit {
  self.controls.push(control)
}
