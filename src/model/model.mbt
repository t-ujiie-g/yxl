///|
/// A cell's value in the minimal model: text, a number, a boolean, or a
/// date/time. A `Date` is stored as civil components; the emitter renders it to
/// an Excel serial using the workbook's date system. Richer kinds (formulas,
/// error literals) arrive later.
pub(all) enum CellValue {
  Text(String)
  Number(Double)
  Bool(Bool)
  Date(@units.DateTime)
  /// An Excel error literal, e.g. `#DIV/0!` or `#N/A`.
  Error(String)
  /// A formula Excel recomputes on open (stored without a leading `=`), with an
  /// optional cached result (a scalar value) shown until then.
  Formula(formula~ : String, cached~ : CellValue?)
  /// A single string built from runs, each with its own optional font — Excel's
  /// inline rich text. Ordered; at least one run.
  RichText(Array[RichRun])
} derive(Eq, Debug)

///|
/// One run of rich text: a piece of text and the font it is drawn in (`None`
/// inherits the cell's font). Runs concatenate into the cell's string.
pub(all) struct RichRun {
  text : String
  font : Font?
} derive(Eq, Hash, Debug)

///|
/// A single populated cell: where it sits, what it holds, and an optional style
/// (font, fill, borders, alignment, number format). `None` means the default
/// (General) style. Equal styles compile to a single shared `cellXfs` id
/// (ADR-004).
pub(all) struct Cell {
  pos : @units.CellRef
  value : CellValue
  style : Style?
} derive(Eq, Debug)

///|
/// The deepest outline (grouping) level Excel accepts on a column or row;
/// level 0 means ungrouped (ECMA-376 §18.3.1.13, §18.3.1.73).
pub let max_outline_level : Int = 7

///|
/// One band of columns or rows: an inclusive 1-based span (`first == last` for a
/// single column/row) and what the spec set on it. Every property is optional;
/// `None` leaves Excel's default in place.
///
/// - `style` — a default style the band's cells inherit unless they set their
///   own. Equal styles compile to a single shared `cellXfs` id (ADR-004).
/// - `size` — a column width in character units, or a row height in points.
/// - `hidden` — `true` hides the band.
/// - `outline_level` — the grouping depth (0 to `max_outline_level`), which
///   Excel draws as a collapsible outline bracket.
///
/// Whether the band is columns or rows is fixed by which `Sheet` list holds it.
pub(all) struct AxisBand {
  first : Int
  last : Int
  style : Style?
  size : Double?
  hidden : Bool?
  outline_level : Int?
} derive(Eq, Debug)

///|
/// A rectangular block of cells, addressed by its top-left and bottom-right
/// corners (canonical: `top_left` is at or above-left of `bottom_right`). Used
/// wherever the spec names a region — a merge, a print area.
pub(all) struct CellRange {
  top_left : @units.CellRef
  bottom_right : @units.CellRef
} derive(Eq, Debug)

///|
/// The range in A1 notation (`A1:B9`), unqualified and relative — the form the
/// spec itself uses.
pub fn CellRange::to_a1(self : CellRange) -> String {
  self.top_left.to_a1() + ":" + self.bottom_right.to_a1()
}

///|
/// How Excel shows a sheet in the tab bar (ECMA-376 §18.18.68,
/// `ST_SheetState`): visible; hidden, which the user can undo from the tab
/// context menu; or very hidden, which only VBA can undo. A workbook must keep
/// at least one visible sheet.
pub(all) enum SheetVisibility {
  Visible
  Hidden
  VeryHidden
} derive(Eq, Debug)

///|
/// How a sheet's viewport is divided (ECMA-376 §18.3.1.66, `pane`):
///
/// - `Freeze(cell)` — the rows above and the columns left of `cell` stay put
///   while the rest scrolls, exactly as Excel's "Freeze Panes" does with that
///   cell selected. `A1` would freeze nothing.
/// - `Split(x, y)` — a draggable splitter, positioned in points from the sheet's
///   top-left corner (`0` on an axis leaves that axis unsplit). Points, not a
///   cell, because a split falls wherever the user drags it, not on a boundary.
pub(all) enum Panes {
  Freeze(@units.CellRef)
  Split(x~ : Double, y~ : Double)
} derive(Eq, Debug)

///|
/// One worksheet: a name, the cells written to it (kept in insertion order),
/// the column and row bands laid over them (see `AxisBand`), merged-cell
/// ranges, and how the sheet presents itself — tab visibility and color, frozen
/// or split panes, and whether gridlines show. Turning these into the final
/// workbook layout is the emitter's job.
pub(all) struct Sheet {
  name : String
  cells : Array[Cell]
  columns : Array[AxisBand]
  rows : Array[AxisBand]
  merges : Array[CellRange]
  visibility : SheetVisibility
  /// How the sheet prints; `None` keeps Excel's defaults throughout.
  mut page : PageSetup?
  /// Frozen or split panes; `None` leaves the sheet unsplit.
  mut panes : Panes?
  /// Whether the on-screen gridlines show; `None` keeps Excel's default (they
  /// do). This is the screen grid, not cell borders, which are part of a style.
  mut gridlines : Bool?
  /// The tab's color; `None` keeps Excel's default (no color).
  mut tab_color : @units.Color?
  /// The range Excel puts filter dropdowns over (its top row is the header);
  /// `None` leaves the sheet unfiltered. A sheet has at most one.
  mut filter : CellRange?
  /// Data validations, in declaration order. Ranges may overlap — Excel keeps
  /// them all, and the last one written wins where they do.
  validations : Array[Validation]
  /// Hyperlinks, one per cell, in declaration order.
  links : Array[Link]
  /// Conditional formats, in declaration order — which is priority order, so an
  /// earlier rule wins where two match the same cell.
  conditional_formats : Array[ConditionalFormat]
  /// Notes attached to cells, in declaration order.
  comments : Array[Comment]
  /// Excel tables over the sheet's regions, in declaration order. Ranges may not
  /// overlap — Excel refuses a workbook whose tables do.
  tables : Array[Table]
  /// Charts anchored on the sheet, in declaration order.
  charts : Array[Chart]
  /// Images anchored on the sheet, in declaration order.
  images : Array[Image]
  /// Shapes floating over the sheet, in declaration order.
  shapes : Array[Shape]
  /// Pivot tables placed on the sheet, in declaration order.
  pivots : Array[Pivot]
  /// What a reader may still do once the sheet is protected; `None` leaves the
  /// sheet unprotected.
  mut protection : SheetProtection?
} derive(Eq, Debug)

///|
/// A workbook-level named definition (ADR-012): a name and what it refers to — a
/// constant (`Text`/`Number`/`Bool`/`Date`) or a formula (`Formula`, whose
/// `cached` is unused here). It compiles to an Excel *defined name* the whole
/// workbook shares; a cell references it with the formula `=name` (ADR-013).
pub(all) struct DefinedName {
  name : String
  refers_to : CellValue
} derive(Eq, Debug)

///|
/// The longest name Excel accepts for a defined name — and for a table name,
/// which shares the same namespace and the same limit.
pub let max_defined_name_length : Int = 255

///|
/// A workbook: an ordered list of sheets — the order is the order of the tabs —
/// the date system that governs how dates serialize, and any workbook-level
/// defined names. This is the entire input to the emitter seam
/// (`model -> bytes`, ADR-002).
pub(all) struct Workbook {
  sheets : Array[Sheet]
  date_system : @units.DateSystem
  /// The workbook's default font face name (`None` keeps the backend default).
  /// Only the name is a workbook-level default; size/color/etc. are per-style.
  default_font : String?
  /// Named definitions shared across the workbook, in declaration order
  /// (deterministic). A reference cell holds `=name`; Excel resolves the name.
  defined_names : Array[DefinedName]
  /// The sheet selected when the workbook opens, by name (`None` selects the
  /// first sheet). The emitter resolves it to Excel's `activeTab` index.
  mut active_sheet : String?
  /// What the workbook says about itself; `None` writes no properties.
  mut properties : DocumentProperties?
  /// How Excel recalculates on open; `None` keeps its defaults.
  mut calc : CalcSettings?
  /// What a reader may not do to the workbook itself; `None` leaves it open.
  mut protection : WorkbookProtection?
} derive(Eq, Debug)

///|
/// The sheet declared under `name`, or `None` — the lookup every construct
/// that names a sheet (a pivot source, a chart series, a link target) shares.
pub fn Workbook::sheet(self : Workbook, name : String) -> Sheet? {
  self.sheets.iter().find_first(sheet => sheet.name == name)
}

///|
/// A new, empty workbook. Defaults to the 1900 date system, the backend's
/// default font, and the first sheet active.
pub fn Workbook::new(
  date_system? : @units.DateSystem = Date1900,
  default_font? : String,
) -> Workbook {
  {
    sheets: [],
    date_system,
    default_font,
    defined_names: [],
    active_sheet: None,
    properties: None,
    calc: None,
    protection: None,
  }
}

///|
/// Select, by name, the sheet Excel opens on. The name must be one of the
/// workbook's sheets; callers validate that (the loader raises a diagnostic).
pub fn Workbook::set_active_sheet(self : Workbook, name : String) -> Unit {
  self.active_sheet = Some(name)
}

///|
/// Set what the workbook says about itself.
pub fn Workbook::set_properties(
  self : Workbook,
  properties : DocumentProperties,
) -> Unit {
  self.properties = Some(properties)
}

///|
/// Lock the workbook's structure, its windows, or both.
pub fn Workbook::set_protection(
  self : Workbook,
  protection : WorkbookProtection,
) -> Unit {
  self.protection = Some(protection)
}

///|
/// Set how Excel recalculates the workbook.
pub fn Workbook::set_calc(self : Workbook, calc : CalcSettings) -> Unit {
  self.calc = Some(calc)
}

///|
/// Register a workbook-level defined name pointing at a constant or formula
/// (ADR-013). Appended in call order so emission is deterministic.
pub fn Workbook::add_defined_name(
  self : Workbook,
  name : String,
  refers_to : CellValue,
) -> Unit {
  self.defined_names.push({ name, refers_to })
}

///|
/// Append a new empty sheet and return it so cells can be written to it. Sheets
/// appear in Excel in the order they are added. The returned sheet shares the
/// workbook's storage, so `set` on it is visible in the workbook.
pub fn Workbook::add_sheet(
  self : Workbook,
  name : String,
  visibility? : SheetVisibility = Visible,
) -> Sheet {
  let sheet = Sheet::new(name, visibility~)
  self.sheets.push(sheet)
  sheet
}

///|
/// A new, empty sheet with the given name, visible unless told otherwise.
pub fn Sheet::new(
  name : String,
  visibility? : SheetVisibility = Visible,
) -> Sheet {
  {
    name,
    cells: [],
    columns: [],
    rows: [],
    merges: [],
    visibility,
    page: None,
    panes: None,
    gridlines: None,
    tab_color: None,
    filter: None,
    validations: [],
    links: [],
    conditional_formats: [],
    comments: [],
    tables: [],
    charts: [],
    images: [],
    shapes: [],
    pivots: [],
    protection: None,
  }
}

///|
/// Set how the sheet prints.
pub fn Sheet::set_page_setup(self : Sheet, page : PageSetup) -> Unit {
  self.page = Some(page)
}

///|
/// Freeze or split the sheet's viewport.
pub fn Sheet::set_panes(self : Sheet, panes : Panes) -> Unit {
  self.panes = Some(panes)
}

///|
/// Show or hide the on-screen gridlines.
pub fn Sheet::set_gridlines(self : Sheet, shown : Bool) -> Unit {
  self.gridlines = Some(shown)
}

///|
/// Color the sheet's tab.
pub fn Sheet::set_tab_color(self : Sheet, color : @units.Color) -> Unit {
  self.tab_color = Some(color)
}

///|
/// Put Excel's filter dropdowns over a range, whose top row is read as the
/// header. Replaces any previous one: Excel keeps a single auto filter per
/// sheet.
pub fn Sheet::set_filter(self : Sheet, range : CellRange) -> Unit {
  self.filter = Some(range)
}

///|
/// Add a data validation over a range. Appended in call order so emission is
/// deterministic.
pub fn Sheet::add_validation(self : Sheet, validation : Validation) -> Unit {
  self.validations.push(validation)
}

///|
/// Add a conditional format over a range. Appended in call order, which Excel
/// reads as priority order.
pub fn Sheet::add_conditional_format(
  self : Sheet,
  format : ConditionalFormat,
) -> Unit {
  self.conditional_formats.push(format)
}

///|
/// Declare a region of the sheet an Excel table. The cells it covers are written
/// as usual; this only says what the region is.
pub fn Sheet::add_table(self : Sheet, table : Table) -> Unit {
  self.tables.push(table)
}

///|
/// Anchor a chart on the sheet. It floats above the grid, so the cells under it
/// keep whatever they hold.
pub fn Sheet::add_chart(self : Sheet, chart : Chart) -> Unit {
  self.charts.push(chart)
}

///|
/// Anchor an image on the sheet. Like a chart, it floats above the grid.
pub fn Sheet::add_image(self : Sheet, image : Image) -> Unit {
  self.images.push(image)
}

///|
/// Place a pivot table on the sheet. The cells it summarizes are elsewhere —
/// possibly on another sheet — and are written as usual.
pub fn Sheet::add_pivot(self : Sheet, pivot : Pivot) -> Unit {
  self.pivots.push(pivot)
}

///|
/// Protect the sheet. Only cells whose style says `locked` are frozen by it,
/// which is every cell unless a style says otherwise.
pub fn Sheet::set_protection(
  self : Sheet,
  protection : SheetProtection,
) -> Unit {
  self.protection = Some(protection)
}

///|
/// Attach a note to a cell. The cell keeps whatever value it was given.
pub fn Sheet::add_comment(
  self : Sheet,
  at : @units.CellRef,
  text : String,
  author? : String,
) -> Unit {
  self.comments.push({ at, text, author })
}

///|
/// Link a cell to a URL or an in-workbook location. The cell keeps whatever
/// value it was given; a link adds no text of its own.
pub fn Sheet::add_link(
  self : Sheet,
  at : @units.CellRef,
  target : LinkTarget,
  tip? : String,
) -> Unit {
  self.links.push({ at, target, tip })
}

///|
/// Lay a band over an inclusive span of columns (1-based): a default style, a
/// width in character units, a hidden flag, and an outline level. Omitted
/// properties leave Excel's default.
pub fn Sheet::set_column_band(
  self : Sheet,
  first~ : Int,
  last~ : Int,
  style? : Style,
  width? : Double,
  hidden? : Bool,
  outline_level? : Int,
) -> Unit {
  self.columns.push({ first, last, style, size: width, hidden, outline_level })
}

///|
/// Lay a band over an inclusive span of rows (1-based): a default style, a
/// height in points, a hidden flag, and an outline level. Omitted properties
/// leave Excel's default.
pub fn Sheet::set_row_band(
  self : Sheet,
  first~ : Int,
  last~ : Int,
  style? : Style,
  height? : Double,
  hidden? : Bool,
  outline_level? : Int,
) -> Unit {
  self.rows.push({ first, last, style, size: height, hidden, outline_level })
}

///|
/// Merge a rectangular block of cells, given its two corners (any opposite pair;
/// stored canonically as top-left / bottom-right).
pub fn Sheet::merge(
  self : Sheet,
  corner1 : @units.CellRef,
  corner2 : @units.CellRef,
) -> Unit {
  let (top_left, bottom_right) = @units.CellRef::rect(corner1, corner2)
  self.merges.push({ top_left, bottom_right })
}

///|
/// Write a value at a cell reference, appending it to the sheet's cells. Pass
/// `style=` for a full style, or `format=` as a shorthand for a number-format-
/// only style. If both are given, an explicit `style` wins; a `format` fills in
/// only when the style leaves the number format unset. An empty resulting style
/// is dropped so the cell stays on the default style.
pub fn Sheet::set(
  self : Sheet,
  pos : @units.CellRef,
  value : CellValue,
  format? : String,
  style? : Style,
) -> Unit {
  let combined = match (style, format) {
    (Some(s), Some(code)) =>
      if s.number_format is None {
        Some({ ..s, number_format: Some(code) })
      } else {
        Some(s)
      }
    (Some(s), None) => Some(s)
    (None, Some(code)) => Some(Style::number_format(code))
    (None, None) => None
  }
  let style = match combined {
    Some(s) if s.is_empty() => None
    other => other
  }
  self.cells.push({ pos, value, style })
}
