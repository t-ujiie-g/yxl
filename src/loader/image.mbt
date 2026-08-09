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
  let at = anchor_cell(entries, file~, subject="an image", noun="image")
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
/// A sheet's `background: <path>` — an image tiled behind the cells. The same
/// trip an `images:` file makes: format from the extension, bytes through the
/// resolver, an empty file refused.
fn load_background(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  read_bytes~ : BytesResolver,
) -> Unit raise {
  let context = "sheet 'background'"
  let path = expect_string(node, file~, context~)
  let format = image_format(path, file~, context~)
  let read = read_bytes(file, path)
  guard read.data.length() > 0 else {
    raise schema_error(file~, "\{context} reads '\{read.name}', which is empty")
  }
  sheet.set_background({ data: read.data, format })
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
      "\{context} names '\{path}', whose format '\{format}' Excel does not store (expected \{or_list(@model.image_formats)})",
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
  guard scale > 0.0 && scale <= @model.max_image_scale else {
    raise schema_error(
      file~,
      "\{what} must be above 0 and at most \{@model.max_image_scale}, not \{scale}",
    )
  }
  scale
}

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
  // Zero is the floor: a negative offset would place the image outside the
  // cell it is anchored to, which OOXML's anchor cannot express
  // (ECMA-376 §20.5.2.3).
  load_pair(node, file~, what~, read=(value, axis) => {
    expect_pixels(value, file~, what="\{what} '\{axis}'", min=0)
  })
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
