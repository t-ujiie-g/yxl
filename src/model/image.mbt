// Images anchored on a sheet. Unlike everything else a spec places, an image is
// not made of text: the file's bytes are read while the spec loads and carried
// in the model, so the emitter still writes a workbook from memory alone
// (ADR-002, ADR-003).

///|
/// A picture anchored on a sheet.
pub(all) struct Image {
  /// The cell the image's top-left corner sits over. An image floats above the
  /// grid; the cells beneath it keep whatever they hold.
  at : @units.CellRef
  /// The file's bytes, as read.
  data : Bytes
  /// The image's format, as a lower-case extension without the dot (`png`).
  /// Excel decides how to decode the bytes by this, not by inspecting them.
  format : String
  /// The description a screen reader announces, and Excel shows as "Alt Text".
  alt_text : String?
  /// How the image is scaled from its natural size — `1.0` is that size.
  scale_x : Double
  scale_y : Double
  /// Pixels in from the anchor cell's top-left corner.
  offset_x : Int
  offset_y : Int
  /// What happens to the image when the cells under it move or resize.
  positioning : ImagePositioning
} derive(Eq, Debug)

///|
/// What Excel does with an image when the cells beneath it change, spelled as
/// its "Size and Properties" pane spells it.
pub(all) enum ImagePositioning {
  /// "Move but don't size with cells" — Excel's default for a pasted image.
  Move
  /// "Move and size with cells".
  MoveAndSize
  /// "Don't move or size with cells".
  Fixed
} derive(Eq, Debug)

///|
/// The image formats Excel stores, by the extension that names each. Listed here
/// so an unsupported file is a diagnostic against the spec rather than an error
/// from inside the emitter (ADR-006); checked against the backend by a test.
pub let image_formats : Array[String] = [
  "bmp", "emf", "emz", "gif", "ico", "jpeg", "jpg", "png", "svg", "tif", "tiff",
  "wmf", "wmz",
]

///|
/// A sheet's background: an image tiled behind the cells, like a watermark.
/// Excel shows it on screen but never prints it. Same arrangement as an
/// `Image`: the bytes are read while the spec loads, so the emitter writes
/// from memory alone (ADR-003).
pub(all) struct SheetBackground {
  /// The file's bytes, as read.
  data : Bytes
  /// The image's format, as a lower-case extension without the dot (`png`).
  format : String
} derive(Eq, Debug)

///|
/// Tile an image behind the sheet's cells.
pub fn Sheet::set_background(
  self : Sheet,
  background : SheetBackground,
) -> Unit {
  self.background = Some(background)
}

///|
/// A ceiling on a drawing's size or offset in pixels — charts and images alike —
/// well past any usable value: it exists so an absurd number is a diagnostic
/// rather than a drawing Excel cannot place.
pub let max_drawing_pixels : Int = 20000

///|
/// The largest image scale a spec may ask for. Excel's own dialog stops here,
/// and past it an image is bigger than any sheet it could sit on.
pub let max_image_scale : Double = 100.0
