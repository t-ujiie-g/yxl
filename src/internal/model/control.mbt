///|
/// A form control. The loader admits only the field combinations Excel's
/// "Format Control" dialog offers per kind; `link` is same-sheet only, and `None`
/// keeps the backend's default.
pub(all) struct FormControl {
  at : @units.CellRef
  kind : FormControlKind
  text : String?
  checked : Bool?
  link : @units.CellRef?
  width : Int32?
  height : Int32?
  min : Int32?
  max : Int32?
  step : Int32?
  page : Int32?
  value : Int32?
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
pub let max_form_control_value : Int32 = 30000

///|
/// Place a form control on the sheet.
pub fn Sheet::add_control(self : Sheet, control : FormControl) -> Unit {
  self.controls.push(control)
}
