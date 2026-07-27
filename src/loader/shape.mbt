// Loading a sheet's `shapes:` — a preset geometry floating over the grid. The
// geometry name is checked against the model's preset table, because the
// backend writes it into the file unchecked and Excel repairs a workbook whose
// geometry it does not know — and the geometries the backend itself would
// corrupt are refused by name (ADR-006).

///|
/// A sheet's `shapes:` — a sequence of shapes, each anchored at a cell.
fn load_shapes(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'shapes'") {
    sheet.add_shape(load_shape(item, file~))
  }
}

///|
/// One `shapes:` entry: where it sits, which geometry it is, and how it looks.
fn load_shape(
  node : @yaml.Node,
  file~ : String,
) -> @model.Shape raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a shape")
  guard find_key(entries, "at") is Some(at_node) else {
    raise schema_error(file~, "a shape is missing required key 'at'")
  }
  let at = expect_cell_ref(
    expect_string(at_node, file~, context="shape 'at'"),
    file~,
    what="shape 'at'",
  )
  let context = "shape at '\{at.to_a1()}'"
  let mut preset = None
  let mut text = None
  let mut width = None
  let mut height = None
  let mut fill = None
  let mut line_color = None
  let mut line_width = None
  let mut alt_text = None
  let mut positioning = @model.Move
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "kind" => {
        let written = expect_string(value, file~, context="\{context} 'kind'")
        // The geometries the backend would corrupt are refused by name, so the
        // author gets the reason instead of "unknown" (ADR-006).
        for entry in @model.unwritable_shape_presets {
          let (name, token) = entry
          if name == written {
            raise schema_error(
              file~,
              "\{context} asks for '\{written}', whose DrawingML token '\{token}' the Excel backend lowercases into one Excel does not recognize — pick a geometry whose token has no capitals, or wait for the upstream fix",
            )
          }
        }
        preset = Some(
          named(
            @model.shape_presets,
            written,
            file~,
            what="shape kind",
            context~,
          ),
        )
      }
      "text" => text = Some(load_shape_text(value, file~, context~))
      "size" => {
        let (w, h) = load_shape_size(value, file~, context~)
        width = Some(w)
        height = Some(h)
      }
      "fill" => fill = Some(expect_color(value, file~, what="'fill'", context~))
      "line" => {
        let (color, points) = load_shape_line(value, file~, context~)
        line_color = Some(color)
        line_width = points
      }
      "alt" =>
        alt_text = Some(expect_string(value, file~, context="\{context} 'alt'"))
      "positioning" =>
        positioning = named(
          image_positionings,
          expect_string(value, file~, context="\{context} 'positioning'"),
          file~,
          what="shape positioning",
          context~,
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'kind', 'text', 'size', 'fill', 'line', 'alt', or 'positioning')",
        )
    }
  }
  guard preset is Some(preset) else {
    raise schema_error(file~, "\{context} is missing required key 'kind'")
  }
  {
    at,
    preset,
    text,
    width,
    height,
    fill,
    line_color,
    line_width,
    alt_text,
    positioning,
  }
}

///|
/// A shape's `text:` — one plain string, or a sequence of lines, each a plain
/// string or a `{ text, font }` mapping like a cell's rich run. A sequence
/// entry is its own *line*: the backend writes one paragraph per run, so one
/// font covers one line.
fn load_shape_text(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ShapeText raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => Plain(text)
    @yaml.Seq(items) => {
      guard !items.is_empty() else {
        raise schema_error(file~, "\{context} 'text' needs at least one line")
      }
      let lines = []
      for item in items {
        lines.push(load_rich_run(item, file~, owner=context))
      }
      Lines(lines)
    }
    _ =>
      raise schema_error(
        file~,
        "\{context} 'text' must be text or a sequence of lines",
      )
  }
}

///|
/// A shape's `size:` — both dimensions, in pixels. Required together: leaving
/// one out would silently pair it with the backend's default.
fn load_shape_size(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> (Int, Int) raise @diag.SchemaError {
  let what = "\{context} 'size'"
  let mut width = None
  let mut height = None
  for entry in expect_map(node, file~, context=what) {
    let (key, value) = entry
    let pixels = match key {
      "width" | "height" =>
        expect_pixels(value, file~, what="\{what} '\{key}'", min=1)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{what} (expected 'width' or 'height')",
        )
    }
    if key == "width" {
      width = Some(pixels)
    } else {
      height = Some(pixels)
    }
  }
  guard width is Some(width) && height is Some(height) else {
    raise schema_error(file~, "\{what} needs both 'width' and 'height'")
  }
  (width, height)
}

///|
/// A shape's `line:` — a hex colour shorthand, or `{ color, width }` with the
/// width in points.
fn load_shape_line(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> (@units.Color, Double?) raise @diag.SchemaError {
  let what = "\{context} 'line'"
  match node {
    @yaml.Str(_) => (expect_color(node, file~, what="'line'", context~), None)
    @yaml.Map(entries) => {
      let mut color = None
      let mut width = None
      for entry in entries {
        let (key, value) = entry
        match key {
          "color" =>
            color = Some(
              expect_color(value, file~, what="'color'", context=what),
            )
          "width" => {
            let points = expect_number(value, file~, context="\{what} 'width'")
            guard points > 0.0 else {
              raise schema_error(
                file~,
                "\{what} 'width' must be above 0 (points), not \{points}",
              )
            }
            width = Some(points)
          }
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in \{what} (expected 'color' or 'width')",
            )
        }
      }
      guard color is Some(color) else {
        raise schema_error(file~, "\{what} needs a 'color'")
      }
      (color, width)
    }
    _ => raise schema_error(file~, "\{what} must be a hex color or a mapping")
  }
}
