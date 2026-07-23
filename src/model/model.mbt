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
/// One worksheet: a name, the cells written to it (kept in insertion order), and
/// any default styles for whole columns or rows. Turning these into the final
/// workbook layout is the emitter's job.
pub(all) struct Sheet {
  name : String
  cells : Array[Cell]
  column_styles : Array[AxisStyle]
  row_styles : Array[AxisStyle]
} derive(Eq, Debug)

///|
/// A workbook: an ordered list of sheets plus the date system that governs how
/// dates serialize. This is the entire input to the emitter seam (`model ->
/// bytes`, ADR-002).
pub(all) struct Workbook {
  sheets : Array[Sheet]
  date_system : @units.DateSystem
  /// The workbook's default font face name (`None` keeps the backend default).
  /// Only the name is a workbook-level default; size/color/etc. are per-style.
  default_font : String?
} derive(Eq, Debug)

///|
/// A new, empty workbook. Defaults to the 1900 date system and the backend's
/// default font.
pub fn Workbook::new(
  date_system? : @units.DateSystem = Date1900,
  default_font? : String,
) -> Workbook {
  { sheets: [], date_system, default_font }
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
  { name, cells: [], column_styles: [], row_styles: [] }
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
