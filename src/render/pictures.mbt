// Rendering the pictures a workbook carries: the `images:` blocks and the sheet
// backgrounds, each naming a file that goes out beside the spec.
//
// Unlike a CSV table this is not an inference — the model holds the bytes
// because the workbook did, so there is nothing to decide. What is invented is
// only the *file name*, which the workbook does not carry: Excel keeps its
// pictures as numbered parts (`image1.png`), so the name here is built from
// where the picture sits rather than recovered.

///|
/// One picture the spec will name, and the bytes it names.
pub(all) struct Picture {
  /// The path the spec names it by, relative to the spec itself.
  path : String
  content : Bytes
}

///|
/// The pictures a workbook carries, with the paths the rendered spec uses.
///
/// The paths are assigned here rather than while rendering so that `render` and
/// the caller writing the files agree without either guessing: this returns
/// both, and `workbook` takes the same list back.
pub fn pictures(wb : @model.Workbook) -> Array[Picture] {
  let taken : Map[String, Unit] = Map([])
  let pictures = []
  for sheet in wb.sheets {
    for image in sheet.images {
      pictures.push(
        picture(
          taken,
          "\{sheet_stem(sheet.name)}_\{image.at.to_a1().to_lower()}",
          image.format,
          image.data,
        ),
      )
    }
    if sheet.background is Some(background) {
      pictures.push(
        picture(
          taken,
          "\{sheet_stem(sheet.name)}_background",
          background.format,
          background.data,
        ),
      )
    }
  }
  pictures
}

///|
/// One picture under `assets/`, with a number added where the name is taken.
fn picture(
  taken : Map[String, Unit],
  stem : String,
  format : String,
  content : Bytes,
) -> Picture {
  let mut path = "assets/\{stem}.\{format}"
  let mut suffix = 2
  while taken.get(path) is Some(_) {
    path = "assets/\{stem}_\{suffix}.\{format}"
    suffix += 1
  }
  taken[path] = ()
  { path, content }
}

///|
/// A sheet's name as the first half of a file name — the same flattening the
/// CSV tables use, so a workbook's companions read as one set rather than two.
fn sheet_stem(sheet_name : String) -> String {
  let out = StringBuilder::new()
  for ch in sheet_name {
    if ch is ('a'..='z' | '0'..='9') {
      out.write_char(ch)
    } else if ch is ('A'..='Z') {
      out.write_char(ch.to_ascii_lowercase())
    } else {
      out.write_char('_')
    }
  }
  let name = out.to_string()
  if name.is_empty() {
    "sheet"
  } else {
    name
  }
}

///|
/// A sheet's `images:` block, given the paths already assigned to its pictures.
/// `next` hands out the next path each call, in the order `pictures` built them.
fn images(sheet : @model.Sheet, next : () -> String?) -> @yaml.Node {
  let rendered = []
  for image in sheet.images {
    let entries = [("at", @yaml.Str(image.at.to_a1()))]
    match next() {
      Some(path) => entries.push(("file", @yaml.Str(path)))
      // Cannot happen: the paths are built from the same list in the same order.
      None => ()
    }
    if image.alt_text is Some(alt) {
      entries.push(("alt", @yaml.Str(alt)))
    }
    if image.scale_x != 1.0 || image.scale_y != 1.0 {
      entries.push(
        if image.scale_x == image.scale_y {
          ("scale", number(image.scale_x))
        } else {
          (
            "scale",
            @yaml.Map([
              ("x", number(image.scale_x)),
              ("y", number(image.scale_y)),
            ]),
          )
        },
      )
    }
    if image.offset_x != 0 || image.offset_y != 0 {
      entries.push(
        (
          "offset",
          @yaml.Map([
            ("x", @yaml.Int(image.offset_x.to_int64())),
            ("y", @yaml.Int(image.offset_y.to_int64())),
          ]),
        ),
      )
    }
    // `move` is Excel's default and the schema's, so it is left unsaid.
    match image.positioning {
      Move => ()
      MoveAndSize => entries.push(("positioning", @yaml.Str("move_and_size")))
      Fixed => entries.push(("positioning", @yaml.Str("fixed")))
    }
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}
