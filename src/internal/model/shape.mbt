///|
/// A preset-geometry drawing. `preset` is an `ST_ShapeType` token (ECMA-376
/// §20.1.10.56) from `shape_presets`; sizes are pixels, `line_width` points,
/// and `None` keeps the default.
pub(all) struct Shape {
  at : @units.CellRef
  preset : String
  text : ShapeText?
  width : Int32?
  height : Int32?
  fill : @units.Color?
  line_color : @units.Color?
  line_width : Double?
  alt_text : String?
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
/// The preset geometries a spec may name, as (spelling, DrawingML `prst`): a
/// subset of ECMA-376 §20.1.10.56, since an unknown token makes Excel repair
/// the file.
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
