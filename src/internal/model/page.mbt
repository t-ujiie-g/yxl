///|
/// Which way the printed page runs.
pub(all) enum Orientation {
  Portrait
  Landscape
} derive(Eq, Debug)

///|
/// Printed margins, in inches — Excel's own unit here. `header`/`footer` are the
/// distance from the paper edge to the header/footer text, not extra margin.
/// Each is `None` when the spec leaves it to Excel's default.
pub(all) struct PageMargins {
  top : Double?
  bottom : Double?
  left : Double?
  right : Double?
  header : Double?
  footer : Double?
} derive(Eq, Debug)

///|
/// How the sheet is sized onto the paper — the two mutually exclusive halves of
/// Excel's scaling control. A `Percent` lies within
/// `min_page_scale`..`max_page_scale`; a `Fit` shrinks the sheet onto that many
/// pages across and down, where `0` on an axis leaves it unconstrained.
pub(all) enum PageScale {
  Percent(Int32)
  Fit(width~ : Int32, height~ : Int32)
} derive(Eq, Debug)

///|
/// The smallest print scale percentage Excel accepts.
pub let min_page_scale : Int32 = 10

///|
/// The largest print scale percentage Excel accepts.
pub let max_page_scale : Int32 = 400

///|
/// How a sheet prints; an unset field keeps Excel's default. `header`/`footer`
/// use Excel's `&` codes (ECMA-376 §18.3.1.46); a break goes above and left of
/// its cell.
pub(all) struct PageSetup {
  area : CellRange?
  orientation : Orientation?
  margins : PageMargins?
  scale : PageScale?
  header : String?
  footer : String?
  breaks : Array[@units.CellRef]
  title_rows : TitleRows?
} derive(Eq, Debug)

///|
/// The rows printed atop every page, `first` to `last` inclusive
/// (`_xlnm.Print_Titles`, ECMA-376 §18.2.6).
pub(all) struct TitleRows {
  first : Int32
  last : Int32
} derive(Eq, Debug)

///|
/// A page setup that changes nothing.
pub fn PageSetup::empty() -> PageSetup {
  {
    area: None,
    orientation: None,
    margins: None,
    scale: None,
    header: None,
    footer: None,
    breaks: [],
    title_rows: None,
  }
}
