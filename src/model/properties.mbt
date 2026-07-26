// What a workbook says about itself: the document properties a file browser and
// Excel's own info pane show, and how Excel recalculates when it opens.
//
// These are workbook-wide, so they sit beside `Workbook` rather than on a sheet.

///|
/// A workbook's document properties. Every field is optional; an unset one is
/// left out of the file rather than written empty, so a reader can tell "not
/// said" from "said to be blank".
///
/// The names here are the ones a user sees in Excel's info pane, not the OOXML
/// element names underneath: `author` is `dc:creator`, `status` is
/// `cp:contentStatus`.
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
  /// Excel keeps this one apart from the rest, in the *application* properties.
  company : String?
  /// Properties of the author's own devising, in declaration order. Names are
  /// unique, which the YAML parser enforces before this is built.
  custom : Array[CustomProperty]
} derive(Eq, Debug)

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
pub(all) struct CustomProperty {
  name : String
  value : PropertyValue
} derive(Eq, Debug)

///|
/// What a custom property may hold. Excel also has a date type here, which the
/// spec does not expose: it wants a full timestamp with a zone, and a date
/// written without one would have to be guessed at (ADR-006). Write a date as
/// text until that is settled.
pub(all) enum PropertyValue {
  Number(Double)
  Bool(Bool)
  Text(String)
} derive(Eq, Debug)

///|
/// When Excel recalculates formulas (ECMA-376 §18.18.10, `ST_CalcMode`).
///
/// `yxl` emits formulas and never evaluates them, so a workbook set to `Manual`
/// opens showing whatever cached values the spec supplied — which is the reason
/// to set it, on a workbook whose formulas are slow.
pub(all) enum CalcMode {
  /// Recalculate as values change (Excel's default).
  Automatic
  /// Recalculate everything except data tables.
  AutomaticNoTables
  /// Recalculate only when asked.
  Manual
} derive(Eq, Debug)

///|
/// How the workbook calculates. Each field is optional; unset leaves Excel's
/// default.
pub(all) struct CalcSettings {
  mode : CalcMode?
  /// Force a full recalculation the moment the workbook opens, whatever the
  /// mode — useful where the spec supplied no cached values.
  on_load : Bool?
} derive(Eq, Debug)

///|
/// What a reader of a protected sheet may still do. Excel's "Protect Sheet"
/// dialog is a list of tick-boxes, and this is that list: `true` allows the
/// action, `false` blocks it.
///
/// The defaults are Excel's own — selecting cells stays allowed, everything
/// else is blocked — so `protect: {}` behaves the way ticking nothing in that
/// dialog does.
pub(all) struct SheetProtection {
  /// Excel's sheet-protection password. **Not encryption**: it stops accidental
  /// edits and is trivially removed. `None` protects the sheet without one.
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
} derive(Eq, Debug)

///|
/// Sheet protection as Excel's dialog opens it: the sheet is locked, but a
/// reader may still select any cell.
pub fn SheetProtection::new() -> SheetProtection {
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
/// What a reader may not do to the *workbook* — as opposed to a sheet's cells.
/// At least one of the two is set; protecting neither would write nothing.
pub(all) struct WorkbookProtection {
  /// Stop sheets being added, removed, renamed, reordered, or unhidden.
  structure : Bool
  /// Stop the workbook's windows being moved or resized. Excel for Windows has
  /// ignored this since 2013; it is written for older readers.
  windows : Bool
  /// As on a sheet, this is not encryption.
  password : String?
} derive(Eq, Debug)
