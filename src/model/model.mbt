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
/// A default style applied to an inclusive span of columns or rows — the cells
/// in that band that set no style of their own inherit it. `first`/`last` are
/// 1-based and inclusive (a single column/row has `first == last`). Whether the
/// band is columns or rows is determined by which `Sheet` list holds it.
pub(all) struct AxisStyle {
  first : Int
  last : Int
  style : Style
} derive(Eq, Debug)

///|
/// A size given to an inclusive span of columns or rows: a column-width band (in
/// character units) or a row-height band (in points). `first`/`last` are 1-based
/// and inclusive. Like `AxisStyle`, whether it is columns or rows is fixed by
/// which `Sheet` list holds it.
pub(all) struct AxisSize {
  first : Int
  last : Int
  size : Double
} derive(Eq, Debug)

///|
/// A rectangular block of cells merged into one, addressed by its top-left and
/// bottom-right corners (canonical: `top_left` is at or above-left of
/// `bottom_right`). The merged cell shows the top-left cell's value.
pub(all) struct MergeRange {
  top_left : @units.CellRef
  bottom_right : @units.CellRef
} derive(Eq, Debug)

///|
/// One worksheet: a name, the cells written to it (kept in insertion order),
/// default styles for whole columns or rows, column-width / row-height bands, and
/// merged-cell ranges. Turning these into the final workbook layout is the
/// emitter's job.
pub(all) struct Sheet {
  name : String
  cells : Array[Cell]
  column_styles : Array[AxisStyle]
  row_styles : Array[AxisStyle]
  column_widths : Array[AxisSize]
  row_heights : Array[AxisSize]
  merges : Array[MergeRange]
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
/// A workbook: an ordered list of sheets, the date system that governs how dates
/// serialize, and any workbook-level defined names. This is the entire input to
/// the emitter seam (`model -> bytes`, ADR-002).
pub(all) struct Workbook {
  sheets : Array[Sheet]
  date_system : @units.DateSystem
  /// The workbook's default font face name (`None` keeps the backend default).
  /// Only the name is a workbook-level default; size/color/etc. are per-style.
  default_font : String?
  /// Named definitions shared across the workbook, in declaration order
  /// (deterministic). A reference cell holds `=name`; Excel resolves the name.
  defined_names : Array[DefinedName]
} derive(Eq, Debug)

///|
/// A new, empty workbook. Defaults to the 1900 date system and the backend's
/// default font.
pub fn Workbook::new(
  date_system? : @units.DateSystem = Date1900,
  default_font? : String,
) -> Workbook {
  { sheets: [], date_system, default_font, defined_names: [] }
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
/// Append a new empty sheet and return it so cells can be written to it. The
/// returned sheet shares the workbook's storage, so `set` on it is visible in
/// the workbook.
pub fn Workbook::add_sheet(self : Workbook, name : String) -> Sheet {
  let sheet = Sheet::new(name)
  self.sheets.push(sheet)
  sheet
}

///|
/// A new, empty sheet with the given name.
pub fn Sheet::new(name : String) -> Sheet {
  {
    name,
    cells: [],
    column_styles: [],
    row_styles: [],
    column_widths: [],
    row_heights: [],
    merges: [],
  }
}

///|
/// Give an inclusive span of columns (1-based) a default style.
pub fn Sheet::set_column_style(
  self : Sheet,
  first~ : Int,
  last~ : Int,
  style : Style,
) -> Unit {
  self.column_styles.push({ first, last, style })
}

///|
/// Give an inclusive span of rows (1-based) a default style.
pub fn Sheet::set_row_style(
  self : Sheet,
  first~ : Int,
  last~ : Int,
  style : Style,
) -> Unit {
  self.row_styles.push({ first, last, style })
}

///|
/// Set the width (in character units) of an inclusive span of columns (1-based).
pub fn Sheet::set_column_width(
  self : Sheet,
  first~ : Int,
  last~ : Int,
  width : Double,
) -> Unit {
  self.column_widths.push({ first, last, size: width })
}

///|
/// Set the height (in points) of an inclusive span of rows (1-based).
pub fn Sheet::set_row_height(
  self : Sheet,
  first~ : Int,
  last~ : Int,
  height : Double,
) -> Unit {
  self.row_heights.push({ first, last, size: height })
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
