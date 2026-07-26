// Loading a sheet's `images:` — the one place a spec names a file that is not
// text. The bytes are read here, through the resolver the caller supplied, so
// the model that reaches the emitter is complete and the core still opens
// nothing itself (ADR-003).

///|
/// How an image behaves when the cells beneath it change, spelled as Excel's
/// "Size and Properties" pane spells it.
let image_positionings : Array[(String, @model.ImagePositioning)] = [
  ("move", Move),
  ("move_and_size", MoveAndSize),
  ("fixed", Fixed),
]

///|
/// A sheet's `images:` — a sequence of pictures, each anchored at a cell.
fn load_images(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  read_bytes~ : BytesResolver,
) -> Unit raise {
  for item in expect_seq(node, file~, context="'images'") {
    sheet.add_image(load_image(item, file~, read_bytes~))
  }
}

///|
/// One `images:` entry: where it sits, which file it is, and how it is placed.
fn load_image(
  node : @yaml.Node,
  file~ : String,
  read_bytes~ : BytesResolver,
) -> @model.Image raise {
  let entries = expect_map(node, file~, context="an image")
  guard find_key(entries, "at") is Some(at_node) else {
    raise schema_error(file~, "an image is missing required key 'at'")
  }
  let at = expect_cell_ref(
    expect_string(at_node, file~, context="image 'at'"),
    file~,
    what="image 'at'",
  )
  let context = "image at '\{at.to_a1()}'"
  let mut path = None
  let mut alt_text = None
  let mut scale_x = 1.0
  let mut scale_y = 1.0
  let mut offset_x = 0
  let mut offset_y = 0
  let mut positioning = @model.Move
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "file" =>
        path = Some(expect_string(value, file~, context="\{context} 'file'"))
      "alt" =>
        alt_text = Some(expect_string(value, file~, context="\{context} 'alt'"))
      "scale" => {
        let (x, y) = load_image_scale(value, file~, context~)
        scale_x = x
        scale_y = y
      }
      "offset" => {
        let (x, y) = load_offset(value, file~, context~)
        offset_x = x
        offset_y = y
      }
      "positioning" =>
        positioning = named(
          image_positionings,
          expect_string(value, file~, context="\{context} 'positioning'"),
          file~,
          what="image positioning",
          context~,
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'file', 'alt', 'scale', 'offset', or 'positioning')",
        )
    }
  }
  guard path is Some(path) else {
    raise schema_error(file~, "\{context} is missing required key 'file'")
  }
  let format = image_format(path, file~, context~)
  let read = read_bytes(file, path)
  guard read.data.length() > 0 else {
    raise schema_error(file~, "\{context} reads '\{read.name}', which is empty")
  }
  {
    at,
    data: read.data,
    format,
    alt_text,
    scale_x,
    scale_y,
    offset_x,
    offset_y,
    positioning,
  }
}

///|
/// An image's format, taken from its file name. Excel decides how to decode the
/// bytes by this and never inspects them, so a `.png` holding a JPEG is a file
/// Excel will not draw — a mislabelled file is beyond what can be checked here,
/// but an unknown extension is not.
fn image_format(
  path : String,
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  guard path.rev_find(".") is Some(dot) && dot + 1 < path.length() else {
    raise schema_error(
      file~,
      "\{context} names '\{path}', which has no extension to say what format it is",
    )
  }
  let format = path[dot + 1:].to_owned().to_lower()
  guard @model.image_formats.contains(format) else {
    raise schema_error(
      file~,
      "\{context} names '\{path}', whose format '\{format}' Excel does not store (expected \{@model.image_formats.join(", ")})",
    )
  }
  format
}

///|
/// An image's `scale:` — one number for both directions, or `{ x, y }`.
fn load_image_scale(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> (Double, Double) raise @diag.SchemaError {
  let what = "\{context} 'scale'"
  if node is @yaml.Map(_) {
    let (x, y) = load_pair(node, file~, what~, read=(value, axis) => {
      expect_image_scale(value, file~, what="\{what} '\{axis}'")
    })
    return (x, y)
  }
  let scale = expect_image_scale(node, file~, what~)
  (scale, scale)
}

///|
/// A scale factor: positive, and short of the point where Excel's own dialog
/// gives up.
fn expect_image_scale(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> Double raise @diag.SchemaError {
  let scale = expect_number(node, file~, context=what)
  guard scale > 0.0 && scale <= MAX_IMAGE_SCALE else {
    raise schema_error(
      file~,
      "\{what} must be above 0 and at most \{MAX_IMAGE_SCALE}, not \{scale}",
    )
  }
  scale
}

///|
/// The largest scale a spec may ask for. Excel's own dialog stops here, and past
/// it an image is bigger than any sheet it could sit on.
const MAX_IMAGE_SCALE : Double = 100.0

///|
/// An image's `offset:` — pixels in from the anchor cell's top-left corner.
/// Both directions are required, since an offset in one only is `0` in the
/// other and saying so is clearer than leaving it out.
fn load_offset(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> (Int, Int) raise @diag.SchemaError {
  let what = "\{context} 'offset'"
  load_pair(node, file~, what~, read=(value, axis) => {
    expect_offset(value, file~, what="\{what} '\{axis}'")
  })
}

///|
/// An offset in whole pixels. Negative would place the image outside the cell it
/// is anchored to, which OOXML's anchor cannot express (ECMA-376 §20.5.2.3).
fn expect_offset(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> Int raise @diag.SchemaError {
  guard node is @yaml.Int(pixels) else {
    raise schema_error(file~, "\{what} must be a whole number of pixels")
  }
  guard pixels >= 0L && pixels <= MAX_CHART_PIXELS.to_int64() else {
    raise schema_error(
      file~,
      "\{what} must be between 0 and \{MAX_CHART_PIXELS} pixels, not \{pixels}",
    )
  }
  pixels.to_int()
}

///|
/// An `{ x, y }` mapping where both are required — the shape a scale and an
/// offset share. `read` measures one axis, and names it in its own diagnostics.
fn[T] load_pair(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
  read~ : (@yaml.Node, String) -> T raise @diag.SchemaError,
) -> (T, T) raise @diag.SchemaError {
  let mut x = None
  let mut y = None
  for entry in expect_map(node, file~, context=what) {
    let (key, value) = entry
    match key {
      "x" => x = Some(read(value, key))
      "y" => y = Some(read(value, key))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{what} (expected 'x' or 'y')",
        )
    }
  }
  guard x is Some(x) && y is Some(y) else {
    raise schema_error(file~, "\{what} needs both 'x' and 'y'")
  }
  (x, y)
}
