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
/// One cell held apart from the rules that produced it (ADR-018): a deliberate,
/// one-off deviation, naming the sheet and cell it lands on, the facets it
/// replaces, and why.
///
/// `value` and `style` are independent: an unset one leaves whatever the rest of
/// the spec put there, so changing a number keeps the formatting and restyling a
/// cell keeps its value. At least one is set — an override of nothing is a
/// mistake the loader refuses, as is a second override of the same cell.
/// `reason` is free text for a reader; nothing in the compiler reads it.
pub(all) struct Override {
  sheet : String
  at : @units.CellRef
  value : CellValue?
  style : Style?
  reason : String?
} derive(Eq, Debug)

///|
/// A workbook: an ordered list of sheets — the order is the order of the tabs —
/// the date system that governs how dates serialize, any workbook-level defined
/// names, and the overrides laid over the finished cells. This is the entire
/// input to the emitter seam (`model -> bytes`, ADR-002).
///
/// Only the *name* of `default_font` is a workbook-level default; size, colour
/// and the rest are per-style. `defined_names` is in declaration order, so
/// emission is deterministic; a reference cell holds `=name` and Excel resolves
/// it. `active_sheet` names the tab Excel opens on, which the emitter resolves
/// to an `activeTab` index. `overrides` are workbook-level because they apply
/// after every sheet's cells, whichever sheet they land on. Every optional field
/// unset keeps Excel's or the backend's default.
pub(all) struct Workbook {
  sheets : Array[Sheet]
  date_system : @units.DateSystem
  default_font : String?
  defined_names : Array[DefinedName]
  overrides : Array[Override]
  mut active_sheet : String?
  mut properties : DocumentProperties?
  mut calc : CalcSettings?
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
    overrides: [],
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
  self.defined_names.push({ name, refers_to, })
}

///|
/// Lay one deliberate deviation over a cell. Appended in declaration order; the
/// emitter applies them after every construct that writes a cell.
pub fn Workbook::add_override(self : Workbook, entry : Override) -> Unit {
  self.overrides.push(entry)
}

///|
/// The overrides landing on one sheet, in declaration order.
pub fn Workbook::sheet_overrides(
  self : Workbook,
  name : String,
) -> Array[Override] {
  self.overrides.filter(entry => entry.sheet == name)
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
/// One worksheet: a name, the cells written to it (kept in insertion order),
/// the column and row bands laid over them (see `AxisBand`), merged-cell
/// ranges, and how the sheet presents itself — tab visibility and color, frozen
/// or split panes, and whether gridlines show. Turning these into the final
/// workbook layout is the emitter's job.
///
/// Every list below it is in declaration order, and an unset optional keeps
/// Excel's default. Where that order or that overlap means something:
///
/// - `conditional_formats` — declaration order *is* priority order, so an
///   earlier rule wins where two match the same cell.
/// - `validations` — ranges may overlap; Excel keeps them all, and the last one
///   written wins where they do.
/// - `tables` — ranges may not overlap: Excel refuses a workbook whose do.
/// - `formulas` — ranges may not overlap each other or a populated cell, which
///   the loader checks, so the order carries no precedence.
/// - `filter` — a sheet has at most one, and its top row is the header.
/// - `gridlines` — the on-screen grid, not cell borders, which are a style.
/// - `background` — an image tiled behind the cells. Excel shows it on screen
///   and never prints it.
pub(all) struct Sheet {
  name : String
  cells : Array[Cell]
  columns : Array[AxisBand]
  rows : Array[AxisBand]
  merges : Array[CellRange]
  visibility : SheetVisibility
  mut page : PageSetup?
  mut panes : Panes?
  mut gridlines : Bool?
  mut tab_color : @units.Color?
  mut filter : CellRange?
  validations : Array[Validation]
  links : Array[Link]
  conditional_formats : Array[ConditionalFormat]
  comments : Array[Comment]
  tables : Array[Table]
  charts : Array[Chart]
  images : Array[Image]
  shapes : Array[Shape]
  mut background : SheetBackground?
  sparklines : Array[SparklineGroup]
  controls : Array[FormControl]
  slicers : Array[Slicer]
  pivots : Array[Pivot]
  formulas : Array[FormulaRange]
  mut protection : SheetProtection?
} derive(Eq, Debug)

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
    background: None,
    sparklines: [],
    controls: [],
    slicers: [],
    pivots: [],
    formulas: [],
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
/// Fill a formula across a region. The cells it covers are written by the
/// emitter, not held in `cells` — one stored formula stands for the range.
pub fn Sheet::add_formula(self : Sheet, formula : FormulaRange) -> Unit {
  self.formulas.push(formula)
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
  self.comments.push({ at, text, author, })
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
  self.links.push({ at, target, tip, })
}

///|
/// What the bands alone say about one position — the column band's style with
/// the row band's laid over it, or `None` where neither covers it.
///
/// This is what a cell inherits before its own style is laid on top
/// (`docs/spec.md` §4). The emitter resolves it into every written cell, and the
/// reader needs the same answer to tell a cell that agrees with its band from
/// one that deliberately does not.
pub fn Sheet::band_style_at(self : Sheet, at : @units.CellRef) -> Style? {
  match
    (band_covering(self.columns, at.col), band_covering(self.rows, at.row)) {
    (Some(column), Some(row)) => Some(row.over(column))
    (None, row) => row
    (column, None) => column
  }
}

///|
/// The last band covering `index`, or `None`. Later bands win, matching the
/// "whichever comes last wins" rule the sheet keys already follow when two
/// declarations overlap.
fn band_covering(bands : Array[AxisBand], index : Int) -> Style? {
  let mut found = None
  for band in bands {
    if index >= band.first && index <= band.last && band.style is Some(style) {
      found = Some(style)
    }
  }
  found
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
  self.columns.push({ first, last, style, size: width, hidden, outline_level, })
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
  self.rows.push({ first, last, style, size: height, hidden, outline_level, })
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
  self.merges.push({ top_left, bottom_right, })
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
        Some({ ..s, number_format: Some(code), })
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
  self.cells.push({ pos, value, style, })
}
