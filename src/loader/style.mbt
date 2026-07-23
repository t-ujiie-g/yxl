// Style interpretation for the loader: turning a cell's `style:` mapping into a
// `model.Style` (font, fill, borders, alignment). The number format is carried
// separately as the cell's `format:` shorthand and folded into the style by
// `cell.mbt`. Structural loading and the shared `expect_*`/`schema_error`
// helpers live in `loader.mbt`.

///|
/// Parse a cell's `style:` mapping into a model style (without a number format,
/// which the caller supplies from the `format:` shorthand). Keys are `font`,
/// `fill`, `border`, and `align`; anything else is a diagnostic.
fn load_style(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.Style raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="cell '\{reference}' style")
  let mut font = None
  let mut fill = None
  let mut borders = None
  let mut align = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "font" => font = Some(load_font(node, file~, reference~))
      "fill" => fill = Some(load_fill(node, file~, reference~))
      "border" => borders = Some(load_borders(node, file~, reference~))
      "align" => align = Some(load_alignment(node, file~, reference~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in cell '\{reference}' style (expected 'font', 'fill', 'border', or 'align')",
        )
    }
  }
  { font, fill, borders, align, number_format: None }
}

///|
fn load_font(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.Font raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="cell '\{reference}' font")
  let mut bold = None
  let mut italic = None
  let mut underline = None
  let mut strike = None
  let mut size = None
  let mut name = None
  let mut color = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "bold" =>
        bold = Some(
          expect_bool(node, file~, context="cell '\{reference}' font 'bold'"),
        )
      "italic" =>
        italic = Some(
          expect_bool(node, file~, context="cell '\{reference}' font 'italic'"),
        )
      "underline" =>
        underline = Some(
          expect_bool(
            node,
            file~,
            context="cell '\{reference}' font 'underline'",
          ),
        )
      "strike" =>
        strike = Some(
          expect_bool(node, file~, context="cell '\{reference}' font 'strike'"),
        )
      "size" =>
        size = Some(
          expect_number(node, file~, context="cell '\{reference}' font 'size'"),
        )
      "name" =>
        name = Some(
          expect_string(node, file~, context="cell '\{reference}' font 'name'"),
        )
      "color" =>
        color = Some(expect_color(node, file~, what="font 'color'", reference~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in cell '\{reference}' font (expected 'bold', 'italic', 'underline', 'strike', 'size', 'name', or 'color')",
        )
    }
  }
  { bold, italic, underline, strike, size, name, color }
}

///|
/// A fill is a hex color shorthand (`fill: "FFFF00"`) or a `{ color }` mapping.
fn load_fill(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.Fill raise @diag.SchemaError {
  match node {
    @yaml.Str(_) =>
      { color: expect_color(node, file~, what="fill", reference~) }
    @yaml.Map(entries) => {
      let mut color = None
      for entry in entries {
        let (key, node) = entry
        match key {
          "color" =>
            color = Some(
              expect_color(node, file~, what="fill 'color'", reference~),
            )
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in cell '\{reference}' fill (expected 'color')",
            )
        }
      }
      guard color is Some(color) else {
        raise schema_error(file~, "cell '\{reference}' fill needs a 'color'")
      }
      { color, }
    }
    _ =>
      raise schema_error(
        file~,
        "cell '\{reference}' fill must be a hex color or a mapping",
      )
  }
}

///|
fn load_alignment(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.Alignment raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="cell '\{reference}' align")
  let mut horizontal = None
  let mut vertical = None
  let mut wrap = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "horizontal" => horizontal = Some(load_halign(node, file~, reference~))
      "vertical" => vertical = Some(load_valign(node, file~, reference~))
      "wrap" =>
        wrap = Some(
          expect_bool(node, file~, context="cell '\{reference}' align 'wrap'"),
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in cell '\{reference}' align (expected 'horizontal', 'vertical', or 'wrap')",
        )
    }
  }
  { horizontal, vertical, wrap }
}

///|
fn load_halign(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.HAlign raise @diag.SchemaError {
  match
    expect_string(node, file~, context="cell '\{reference}' horizontal align") {
    "left" => Left
    "center" => Center
    "right" => Right
    "fill" => Fill
    "justify" => Justify
    "distributed" => Distributed
    other =>
      raise schema_error(
        file~,
        "cell '\{reference}' has an unknown horizontal alignment '\{other}' (expected 'left', 'center', 'right', 'fill', 'justify', or 'distributed')",
      )
  }
}

///|
fn load_valign(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.VAlign raise @diag.SchemaError {
  match
    expect_string(node, file~, context="cell '\{reference}' vertical align") {
    "top" => Top
    "middle" => Middle
    "bottom" => Bottom
    "justify" => Justify
    "distributed" => Distributed
    other =>
      raise schema_error(
        file~,
        "cell '\{reference}' has an unknown vertical alignment '\{other}' (expected 'top', 'middle', 'bottom', 'justify', or 'distributed')",
      )
  }
}

///|
/// A `border` is a line-style shorthand (`border: thin`, all four sides) or a
/// mapping keyed by side (`all`, `left`, `right`, `top`, `bottom`).
fn load_borders(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.Borders raise @diag.SchemaError {
  match node {
    @yaml.Str(_) => {
      let edge = load_border(node, file~, reference~)
      {
        left: Some(edge),
        right: Some(edge),
        top: Some(edge),
        bottom: Some(edge),
      }
    }
    @yaml.Map(entries) => {
      let mut left = None
      let mut right = None
      let mut top = None
      let mut bottom = None
      for entry in entries {
        let (key, node) = entry
        match key {
          "all" => {
            let edge = load_border(node, file~, reference~)
            left = Some(edge)
            right = Some(edge)
            top = Some(edge)
            bottom = Some(edge)
          }
          "left" => left = Some(load_border(node, file~, reference~))
          "right" => right = Some(load_border(node, file~, reference~))
          "top" => top = Some(load_border(node, file~, reference~))
          "bottom" => bottom = Some(load_border(node, file~, reference~))
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in cell '\{reference}' border (expected 'all', 'left', 'right', 'top', or 'bottom')",
            )
        }
      }
      { left, right, top, bottom }
    }
    _ =>
      raise schema_error(
        file~,
        "cell '\{reference}' border must be a style name or a mapping",
      )
  }
}

///|
/// One border edge: a line-style name shorthand or a `{ style, color }` mapping.
fn load_border(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.Border raise @diag.SchemaError {
  match node {
    @yaml.Str(_) =>
      { style: load_border_style(node, file~, reference~), color: None }
    @yaml.Map(entries) => {
      let mut style = None
      let mut color = None
      for entry in entries {
        let (key, node) = entry
        match key {
          "style" => style = Some(load_border_style(node, file~, reference~))
          "color" =>
            color = Some(
              expect_color(node, file~, what="border 'color'", reference~),
            )
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in cell '\{reference}' border edge (expected 'style' or 'color')",
            )
        }
      }
      guard style is Some(style) else {
        raise schema_error(file~, "cell '\{reference}' border needs a 'style'")
      }
      { style, color }
    }
    _ =>
      raise schema_error(
        file~,
        "cell '\{reference}' border edge must be a style name or a mapping",
      )
  }
}

///|
fn load_border_style(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.BorderStyle raise @diag.SchemaError {
  match expect_string(node, file~, context="cell '\{reference}' border style") {
    "thin" => Thin
    "medium" => Medium
    "thick" => Thick
    "dashed" => Dashed
    "dotted" => Dotted
    "double" => Double
    "hair" => Hair
    other =>
      raise schema_error(
        file~,
        "cell '\{reference}' has an unknown border style '\{other}' (expected 'thin', 'medium', 'thick', 'dashed', 'dotted', 'double', or 'hair')",
      )
  }
}

///|
/// A number scalar (integer or float) as a `Double`.
fn expect_number(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Double raise @diag.SchemaError {
  match node {
    @yaml.Int(number) => number.to_double()
    @yaml.Float(number) => number
    _ => raise schema_error(file~, "\{context} must be a number")
  }
}

///|
/// A hex-color scalar, validated into a `@units.Color`. `what` names the
/// attribute for the diagnostic (e.g. `"font 'color'"`).
fn expect_color(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
  reference~ : String,
) -> @units.Color raise @diag.SchemaError {
  let text = expect_string(node, file~, context="cell '\{reference}' \{what}")
  guard @units.Color::parse(text) is Some(color) else {
    raise schema_error(
      file~,
      "cell '\{reference}' \{what} is not a valid hex color: '\{text}'",
    )
  }
  color
}
