// Shapes floating over the grid: a box, arrow, or callout, optionally carrying
// text. Like an image, a shape decorates the sheet — the cells beneath it keep
// whatever they hold.

///|
/// A drawing anchored on a sheet: a preset geometry with an optional size,
/// fill and line colour, text, and alt text.
pub(all) struct Shape {
  /// The cell the shape's top-left corner sits over.
  at : @units.CellRef
  /// The DrawingML preset geometry token (ECMA-376 §20.1.10.56,
  /// `ST_ShapeType`) — one of `shape_presets`' second halves. The loader only
  /// admits names from that table, because Excel repairs a file whose `prst`
  /// it does not know.
  preset : String
  /// What the shape says, if anything — one plain string, or a list of lines
  /// each in its own font.
  text : ShapeText?
  /// The shape's size in pixels; `None` keeps the backend default (160).
  width : Int?
  height : Int?
  /// The fill colour; `None` keeps the theme default.
  fill : @units.Color?
  /// The outline colour and width (points); `None` keeps the theme default.
  line_color : @units.Color?
  line_width : Double?
  /// The description a screen reader announces, and Excel shows as "Alt Text".
  alt_text : String?
  /// What happens to the shape when the cells under it move or resize — the
  /// same three anchors an image takes.
  positioning : ImagePositioning
} derive(Eq, Debug)

///|
/// A shape's text: one plain string, or a list of lines. Each line is a
/// `RichRun` — its own text in its own font — because that is how the Excel
/// backend lays shape text out: one run per paragraph, so one font per line.
pub(all) enum ShapeText {
  Plain(String)
  Lines(Array[RichRun])
} derive(Eq, Debug)

///|
/// The preset geometries a spec may name, as (spec spelling, DrawingML `prst`
/// token). A deliberate subset of `ST_ShapeType`'s ~180 (ECMA-376
/// §20.1.10.56), twice narrowed: the backend writes the token into `prst=`
/// unchecked, so an unknown one makes Excel repair the file — and it
/// *lowercases* what it writes, so only geometries whose token is already all
/// lower-case survive the trip. The camel-case ones an author will reach for
/// are named in `unwritable_shape_presets` so their refusal can say why.
pub let shape_presets : Array[(String, String)] = [
  ("rectangle", "rect"),
  ("ellipse", "ellipse"),
  ("triangle", "triangle"),
  ("diamond", "diamond"),
  ("parallelogram", "parallelogram"),
  ("trapezoid", "trapezoid"),
  ("pentagon", "pentagon"),
  ("hexagon", "hexagon"),
  ("octagon", "octagon"),
  ("decagon", "decagon"),
  ("star_5", "star5"),
  ("plus", "plus"),
  ("chevron", "chevron"),
  ("cube", "cube"),
  ("can", "can"),
  ("donut", "donut"),
  ("frame", "frame"),
  ("heart", "heart"),
  ("moon", "moon"),
  ("sun", "sun"),
  ("cloud", "cloud"),
  ("pie", "pie"),
  ("line", "line"),
]

///|
/// Geometries the spec names but the backend cannot write: their `ST_ShapeType`
/// token is camel-case, and the backend lowercases every token on the way out
/// (`roundRect` reaches the file as `roundrect`), which Excel does not
/// recognize. Refused by name, with the reason, until that is fixed upstream —
/// the same arrangement as a pivot's `filters:`.
pub let unwritable_shape_presets : Array[(String, String)] = [
  ("rounded_rectangle", "roundRect"),
  ("right_triangle", "rtTriangle"),
  ("arrow_right", "rightArrow"),
  ("arrow_left", "leftArrow"),
  ("arrow_up", "upArrow"),
  ("arrow_down", "downArrow"),
  ("arrow_left_right", "leftRightArrow"),
  ("arrow_up_down", "upDownArrow"),
  ("callout_rectangle", "wedgeRectCallout"),
  ("callout_rounded_rectangle", "wedgeRoundRectCallout"),
  ("callout_ellipse", "wedgeEllipseCallout"),
  ("callout_cloud", "cloudCallout"),
]

///|
/// Anchor a shape on the sheet. Like a chart or an image, it floats above the
/// grid.
pub fn Sheet::add_shape(self : Sheet, shape : Shape) -> Unit {
  self.shapes.push(shape)
}
