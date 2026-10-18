///|
/// A picture floating over `at`; offsets are pixels, scales relative to natural
/// size. Excel decodes by `format`, a lower-case extension without the dot.
pub(all) struct Image {
  at : @units.CellRef
  data : Bytes
  format : String
  alt_text : String?
  scale_x : Double
  scale_y : Double
  offset_x : Int32
  offset_y : Int32
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
/// The image formats Excel stores, by extension, so an unsupported file is a
/// diagnostic rather than an emitter error (ADR-006). A test checks the
/// backend.
pub let image_formats : Array[String] = [
  "bmp", "emf", "emz", "gif", "ico", "jpeg", "jpg", "png", "svg", "tif", "tiff",
  "wmf", "wmz",
]

///|
/// A sheet's background, tiled behind the cells and never printed; `format` as
/// for `Image`.
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
/// A ceiling on a drawing's size or offset in pixels — charts and images alike
/// — well past any usable value: it exists so an absurd number is a diagnostic
/// rather than a drawing Excel cannot place.
pub let max_drawing_pixels : Int32 = 20000

///|
/// The largest image scale a spec may ask for. Excel's own dialog stops here,
/// and past it an image is bigger than any sheet it could sit on.
pub let max_image_scale : Double = 100.0

///|
/// How an image behaves when the cells beneath it change, spelled as Excel's
/// "Size and Properties" pane spells it.
pub let image_positionings : Array[(String, ImagePositioning)] = [
  ("move", Move),
  ("move_and_size", MoveAndSize),
  ("fixed", Fixed),
]
