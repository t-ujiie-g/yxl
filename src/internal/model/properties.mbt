///|
/// A workbook's document properties, named as Excel's info pane names them. An
/// unset one is omitted rather than written empty; `custom` names are unique.
#derive(Eq, Debug)
pub(all) struct DocumentProperties {
  title : String?
  subject : String?
  author : String?
  keywords : String?
  description : String?
  category : String?
  status : String?
  language : String?
  version : String?
  company : String?
  custom : Array[CustomProperty]
}

///|
/// Document properties that say nothing.
pub fn DocumentProperties::empty() -> DocumentProperties {
  {
    title: None,
    subject: None,
    author: None,
    keywords: None,
    description: None,
    category: None,
    status: None,
    language: None,
    version: None,
    company: None,
    custom: [],
  }
}

///|
/// One property of the author's own devising: a name, and a typed value.
#derive(Eq, Debug)
pub(all) struct CustomProperty {
  name : String
  value : PropertyValue
}

///|
/// What a custom property may hold. Excel's date type wants a zoned timestamp
/// the spec would have to guess (ADR-006), so a date is written as text.
#derive(Eq, Debug)
pub(all) enum PropertyValue {
  Number(Double)
  Bool(Bool)
  Text(String)
}

///|
/// When Excel recalculates formulas (ECMA-376 §18.18.10).
#derive(Eq, Debug)
pub(all) enum CalcMode {
  /// Recalculate as values change (Excel's default).
  Automatic
  /// Recalculate everything except data tables.
  AutomaticNoTables
  /// Recalculate only when asked.
  Manual
}

///|
/// How the workbook calculates. Each field is optional; unset leaves Excel's
/// default. `on_load` forces a full recalculation the moment the workbook
/// opens, whatever the mode — useful where the spec supplied no cached values.
#derive(Eq, Debug)
pub(all) struct CalcSettings {
  mode : CalcMode?
  on_load : Bool?
}

///|
/// What a reader of a protected sheet may still do — the "Protect Sheet"
/// dialog's boxes, with its defaults. `password` is not encryption.
#derive(Eq, Debug)
pub(all) struct SheetProtection {
  password : String?
  select_locked_cells : Bool
  select_unlocked_cells : Bool
  format_cells : Bool
  format_columns : Bool
  format_rows : Bool
  insert_columns : Bool
  insert_rows : Bool
  insert_hyperlinks : Bool
  delete_columns : Bool
  delete_rows : Bool
  sort : Bool
  auto_filter : Bool
  pivot_tables : Bool
  edit_objects : Bool
  edit_scenarios : Bool
}

///|
/// Sheet protection as Excel's dialog opens it: the sheet is locked, but a
/// reader may still select any cell.
pub fn SheetProtection::SheetProtection() -> SheetProtection {
  {
    password: None,
    select_locked_cells: true,
    select_unlocked_cells: true,
    format_cells: false,
    format_columns: false,
    format_rows: false,
    insert_columns: false,
    insert_rows: false,
    insert_hyperlinks: false,
    delete_columns: false,
    delete_rows: false,
    sort: false,
    auto_filter: false,
    pivot_tables: false,
    edit_objects: false,
    edit_scenarios: false,
  }
}

///|
/// What a reader may not do to the workbook; at least one of the two is set.
/// `password` is not encryption.
#derive(Eq, Debug)
pub(all) struct WorkbookProtection {
  structure : Bool
  windows : Bool
  password : String?
}
