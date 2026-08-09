///|
/// One picture the spec will name, and the bytes it names: the sheet it belongs
/// to, the cell it is anchored at — `None` for the one tiled behind the sheet,
/// which is anchored nowhere — and the path the spec names it by, relative to
/// the spec itself.
pub(all) struct Picture {
  sheet : String
  at : @units.CellRef?
  path : String
  content : Bytes
}

///|
/// The key a picture is found by while rendering. Keying by where the picture
/// *is* rather than by the order it was built keeps the spec and the files in
/// step without either depending on the other's iteration order.
pub fn Picture::key(sheet : String, at : @units.CellRef?) -> String {
  match at {
    Some(at) => "\{sheet}!\{at.to_a1()}"
    None => "\{sheet}!background"
  }
}

///|
/// The pictures a workbook carries, with the paths the rendered spec uses.
///
/// The paths are assigned here rather than while rendering so that `render` and
/// the caller writing the files agree without either guessing: this returns
/// both, and `workbook` takes the same list back.
pub fn pictures(wb : @model.Workbook) -> Array[Picture] {
  companion_pictures(wb, Names::new())
}

///|
/// The same, against a caller's own name pool rather than a fresh one.
fn companion_pictures(wb : @model.Workbook, names : Names) -> Array[Picture] {
  let pictures = []
  for sheet in wb.sheets {
    let stem = file_stem(sheet.name)
    for image in sheet.images {
      pictures.push({
        sheet: sheet.name,
        at: Some(image.at),
        path: names.claim(
          asset_directory,
          "\{stem}_\{image.at.to_a1().to_lower()}",
          image.format,
        ),
        content: image.data,
      })
    }
    if sheet.background is Some(background) {
      pictures.push({
        sheet: sheet.name,
        at: None,
        path: names.claim(
          asset_directory,
          "\{stem}_background",
          background.format,
        ),
        content: background.data,
      })
    }
  }
  pictures
}

///|
/// A sheet's `images:` block, given the paths already assigned to its pictures,
/// looked up by where each picture sits.
fn images(sheet : @model.Sheet, paths : Map[String, String]) -> @yaml.Node {
  let rendered = []
  for image in sheet.images {
    let entries = [("at", @yaml.Str(image.at.to_a1()))]
    match paths.get(Picture::key(sheet.name, Some(image.at))) {
      Some(path) => entries.push(("file", @yaml.Str(path)))
      // Only when the caller passed no pictures, which `workbook` allows.
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
    positioning(image.positioning, entries)
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}
