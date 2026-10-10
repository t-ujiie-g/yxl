///|
/// A picture anchored on a sheet: `at` is the cell its top-left corner floats
/// over, and the cells beneath it keep whatever they hold. `offset_x`/`offset_y`
/// are pixels in from that corner and `scale_x`/`scale_y` are relative to the
/// image's natural size, which is `1.0`.
///
/// `format` is a lower-case extension without the dot (`png`); Excel decodes the
/// bytes by that rather than by inspecting them. `alt_text` is what a screen
/// reader announces and Excel shows as "Alt Text".
pub(all) struct Image {
  at : @units.CellRef
  data : Bytes
  format : String
  alt_text : String?
  scale_x : Double
  scale_y : Double
  offset_x : Int
  offset_y : Int
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
/// from memory alone (ADR-003), and `format` is a lower-case extension without
/// the dot (`png`).
pub(all) struct SheetBackground {
  data : Bytes
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
