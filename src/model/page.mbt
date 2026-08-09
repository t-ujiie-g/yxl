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
  Percent(Int)
  Fit(width~ : Int, height~ : Int)
} derive(Eq, Debug)

///|
/// The smallest print scale percentage Excel accepts.
pub let min_page_scale : Int = 10

///|
/// The largest print scale percentage Excel accepts.
pub let max_page_scale : Int = 400

///|
/// How a sheet prints: what to print (`area`, `breaks`), how it sits on the
/// paper (`orientation`, `margins`, `scale`), and what runs along the top and
/// bottom of every page (`header`, `footer`, in Excel's `&`-code syntax —
/// ECMA-376 §18.3.1.46). Everything is optional; an unset field keeps Excel's
/// default. Each of `breaks` puts a manual page break above and to the left of
/// the cell it names.
pub(all) struct PageSetup {
  area : CellRange?
  orientation : Orientation?
  margins : PageMargins?
  scale : PageScale?
  header : String?
  footer : String?
  breaks : Array[@units.CellRef]
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
  }
}
