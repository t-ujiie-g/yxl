// Form controls: a button, check box, or slider sitting over the grid, linked
// to a cell. The value a control writes into its linked cell is what makes a
// sheet a form — the same story `protection: { locked: false }` tells from
// the other side.

///|
/// A form control anchored at a cell. Which fields mean anything depends on
/// the kind — the loader admits only the combinations Excel's own "Format
/// Control" dialog offers.
pub(all) struct FormControl {
  at : @units.CellRef
  kind : FormControlKind
  /// The caption (a button, check box, option button, group box, or label).
  text : String?
  /// Whether a check box or option button starts ticked.
  checked : Bool?
  /// The cell the control writes its value into — a boolean for a check box,
  /// the option's index for an option button, the number for a scroll bar or
  /// spin button. Same-sheet only: the backend refuses a qualified reference.
  link : @units.CellRef?
  /// The control's size in pixels; `None` keeps the backend default.
  width : Int?
  height : Int?
  /// A scroll bar's or spin button's range, step, and starting value —
  /// `page` (a click in the trough) is the scroll bar's alone. All within
  /// 0..=max_form_control_value, Excel's own dialog limit.
  min : Int?
  max : Int?
  step : Int?
  page : Int?
  value : Int?
  /// Lay a scroll bar or spin button sideways.
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
