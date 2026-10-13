///|
/// A cell's value. `Formula` omits the leading `=` and caches what Excel shows
/// before recomputing; `Blank` exists only to wear a style and stays blank to
/// `ISBLANK`.
pub(all) enum CellValue {
  Text(String)
  Number(Double)
  Bool(Bool)
  Date(@units.DateTime)
  /// An Excel error literal, e.g. `#DIV/0!` or `#N/A`.
  Error(String)
  Formula(formula~ : String, cached~ : CellValue?)
  RichText(Array[RichRun])
  Blank
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
pub let max_outline_level : Int32 = 7

///|
/// One band of columns or rows: an inclusive 1-based span and what the spec set
/// on it; `None` keeps Excel's default. The holding `Sheet` list fixes the axis.
pub(all) struct AxisBand {
  first : Int32
  last : Int32
  style : Style?
  size : Double?
  hidden : Bool?
  outline_level : Int32?
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
/// Parse `TopLeft:BottomRight`, the inverse of `to_a1`; corners in either order
/// come back canonical.
pub fn CellRange::parse(text : String) -> CellRange? {
  guard text.split_once(":") is Some((left, right)) else { return None }
  guard @units.CellRef::parse_a1(left.to_owned()) is Some(first) &&
    @units.CellRef::parse_a1(right.to_owned()) is Some(second) else {
    return None
  }
  let (top_left, bottom_right) = @units.CellRef::rect(first, second)
  Some({ top_left, bottom_right, })
}

///|
/// The same, accepting a single cell as the one-cell range it stands for —
/// which is how Excel writes a validation or a conditional format over one cell.
pub fn CellRange::parse_loose(text : String) -> CellRange? {
  match CellRange::parse(text) {
    Some(range) => Some(range)
    None =>
      match @units.CellRef::parse_a1(text) {
        Some(at) => Some({ top_left: at, bottom_right: at, })
        None => None
      }
  }
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
/// How a sheet's viewport is divided (ECMA-376 §18.3.1.66). A `Split` is in
/// points from the top-left, `0` leaving that axis unsplit.
pub(all) enum Panes {
  Freeze(@units.CellRef)
  Split(x~ : Double, y~ : Double)
} derive(Eq, Debug)

///|
/// One formula filled across a region, written as it applies at the top-left;
/// it compiles to a shared formula (ECMA-376 §18.3.1.40, ADR-004).
pub(all) struct FormulaRange {
  at : CellRange
  formula : String
} derive(Eq, Debug)

///|
/// The most cells one `formulas:` range may cover: one full column
/// (ECMA-376 §18.3.1.99). Beyond that the range is a typo.
pub let max_formula_range_cells : Int32 = 1048576
