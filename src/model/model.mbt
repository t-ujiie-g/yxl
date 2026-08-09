///|
/// A cell's value: text, a number, a boolean, a date/time, an Excel error
/// literal, a formula, or rich text. A `Date` is stored as civil components; the
/// emitter renders it to an Excel serial using the workbook's date system.
///
/// A `Formula` is stored without its leading `=`, and its `cached` scalar is
/// what Excel shows until it recomputes on open. `RichText` runs are ordered,
/// and there is at least one. A `Blank` cell exists only so that it can wear a
/// style — a shaded box, a ruled table edge, the blank half of a merged heading
/// — and stays blank to `ISBLANK` and to `COUNTA`.
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
/// Parse `TopLeft:BottomRight` (`A1:B9`) — the inverse of `to_a1`. The corners
/// may be given in either order; the result is canonical. `None` for anything
/// that is not two A1 references around a colon, which the caller turns into
/// whatever its own direction needs: the loader raises a diagnostic, the reader
/// treats it as one more thing the schema will not carry.
pub fn CellRange::parse(text : String) -> CellRange? {
  guard text.split_once(":") is Some((left, right)) else { return None }
  guard @units.CellRef::parse_a1(left.to_owned()) is Some(first) &&
    @units.CellRef::parse_a1(right.to_owned()) is Some(second) else {
    return None
  }
  let (top_left, bottom_right) = @units.CellRef::rect(first, second)
  Some({ top_left, bottom_right })
}

///|
/// The same, accepting a single cell as the one-cell range it stands for —
/// which is how Excel writes a validation or a conditional format over one cell.
pub fn CellRange::parse_loose(text : String) -> CellRange? {
  match CellRange::parse(text) {
    Some(range) => Some(range)
    None =>
      match @units.CellRef::parse_a1(text) {
        Some(at) => Some({ top_left: at, bottom_right: at })
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
/// One formula filled across a region: the formula is written as it applies at
/// the range's **top-left** cell, and every other cell in the range gets it with
/// its relative references shifted by that cell's offset. Absolute references
/// (`$C$2`) do not move. This is Excel's own shared formula (ECMA-376
/// §18.3.1.40), so *Excel* performs the translation on open — the emitter writes
/// the master formula once and marks the rest as followers, which is what makes
/// one spec line compile to one stored formula (ADR-004).
pub(all) struct FormulaRange {
  at : CellRange
  formula : String
} derive(Eq, Debug)

///|
/// The most cells one `formulas:` range may cover — a full Excel column
/// (ECMA-376 §18.3.1.99 puts 1 048 576 rows in a sheet). A filled column is the
/// point of the construct, so the whole of one is allowed; beyond that the range
/// is a typo, and without a ceiling a mistyped `A1:A99999999` would sit there
/// building cells until the machine gave up.
pub let max_formula_range_cells : Int = 1048576
