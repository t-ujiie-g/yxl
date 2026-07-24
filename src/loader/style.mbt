// Style interpretation for the loader: turning a `style:` mapping into a
// `model.Style` (font, fill, borders, alignment). The number format is carried
// separately as a `format:` shorthand and folded into the style by the caller.
// `context` names the owner of the style for diagnostics (e.g. `"cell 'A1'"` or
// `"column 'B'"`), so the same parser serves cell, column, and row styles.
// Structural loading and the shared `expect_*`/`schema_error` helpers live in
// `loader.mbt`.

///|
/// Fold a `style:` mapping and a `format:` number-format shorthand into one
/// model style. The `format:` code sets the style's number format. An entirely
/// empty result becomes `None`, leaving the owner on the default style. Shared
/// by cell, column, and row styles (`context` names the owner in diagnostics).
fn combine_style(
  style_node : @yaml.Node?,
  number_format : String?,
  file~ : String,
  defs~ : Defs,
  context~ : String,
) -> @model.Style? raise @diag.SchemaError {
  let base = match style_node {
    // A bareword names a style definition (ADR-012); a mapping is inline.
    Some(@yaml.Str(name)) =>
      match defs.styles.get(name) {
        Some(style) => style
        None =>
          raise schema_error(
            file~,
            "\{context} references undefined style '\{name}'",
          )
      }
    Some(node) => load_style(node, file~, context~)
    None => @model.Style::empty()
  }
  let combined = match number_format {
    Some(code) => { ..base, number_format: Some(code) }
    None => base
  }
  if combined.is_empty() {
    None
  } else {
    Some(combined)
  }
}

///|
/// Parse a `style:` mapping into a model style (without a number format, which
/// the caller supplies from the `format:` shorthand). Keys are `font`, `fill`,
/// `border`, and `align`; anything else is a diagnostic.
fn load_style(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.Style raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="\{context} style")
  let mut font = None
  let mut fill = None
  let mut borders = None
  let mut align = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "font" => font = Some(load_font(node, file~, context~))
      "fill" => fill = Some(load_fill(node, file~, context~))
      "border" => borders = Some(load_borders(node, file~, context~))
      "align" => align = Some(load_alignment(node, file~, context~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} style (expected 'font', 'fill', 'border', or 'align')",
        )
    }
  }
  { font, fill, borders, align, number_format: None }
}

///|
fn load_font(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.Font raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="\{context} font")
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
        bold = Some(expect_bool(node, file~, context="\{context} font 'bold'"))
      "italic" =>
        italic = Some(
          expect_bool(node, file~, context="\{context} font 'italic'"),
        )
      "underline" =>
        underline = Some(
          expect_bool(node, file~, context="\{context} font 'underline'"),
        )
      "strike" =>
        strike = Some(
          expect_bool(node, file~, context="\{context} font 'strike'"),
        )
      "size" =>
        size = Some(
          expect_number(node, file~, context="\{context} font 'size'"),
        )
      "name" =>
        name = Some(
          expect_string(node, file~, context="\{context} font 'name'"),
        )
      "color" =>
        color = Some(expect_color(node, file~, what="font 'color'", context~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} font (expected 'bold', 'italic', 'underline', 'strike', 'size', 'name', or 'color')",
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
  context~ : String,
) -> @model.Fill raise @diag.SchemaError {
  match node {
    @yaml.Str(_) => { color: expect_color(node, file~, what="fill", context~) }
    @yaml.Map(entries) => {
      let mut color = None
      for entry in entries {
        let (key, node) = entry
        match key {
          "color" =>
            color = Some(
              expect_color(node, file~, what="fill 'color'", context~),
            )
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in \{context} fill (expected 'color')",
            )
        }
      }
      guard color is Some(color) else {
        raise schema_error(file~, "\{context} fill needs a 'color'")
      }
      { color, }
    }
    _ =>
      raise schema_error(
        file~,
        "\{context} fill must be a hex color or a mapping",
      )
  }
}

///|
fn load_alignment(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.Alignment raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="\{context} align")
  let mut horizontal = None
  let mut vertical = None
  let mut wrap = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "horizontal" => horizontal = Some(load_halign(node, file~, context~))
      "vertical" => vertical = Some(load_valign(node, file~, context~))
      "wrap" =>
        wrap = Some(expect_bool(node, file~, context="\{context} align 'wrap'"))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} align (expected 'horizontal', 'vertical', or 'wrap')",
        )
    }
  }
  { horizontal, vertical, wrap }
}

///|
fn load_halign(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.HAlign raise @diag.SchemaError {
  match expect_string(node, file~, context="\{context} horizontal align") {
    "left" => Left
    "center" => Center
    "right" => Right
    "fill" => Fill
    "justify" => Justify
    "distributed" => Distributed
    other =>
      raise schema_error(
        file~,
        "\{context} has an unknown horizontal alignment '\{other}' (expected 'left', 'center', 'right', 'fill', 'justify', or 'distributed')",
      )
  }
}

///|
fn load_valign(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.VAlign raise @diag.SchemaError {
  match expect_string(node, file~, context="\{context} vertical align") {
    "top" => Top
    "middle" => Middle
    "bottom" => Bottom
    "justify" => Justify
    "distributed" => Distributed
    other =>
      raise schema_error(
        file~,
        "\{context} has an unknown vertical alignment '\{other}' (expected 'top', 'middle', 'bottom', 'justify', or 'distributed')",
      )
  }
}

///|
/// A `border` is a line-style shorthand (`border: thin`, all four sides) or a
/// mapping keyed by side (`all`, `left`, `right`, `top`, `bottom`).
fn load_borders(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.Borders raise @diag.SchemaError {
  match node {
    @yaml.Str(_) => {
      let edge = load_border(node, file~, context~)
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
            let edge = load_border(node, file~, context~)
            left = Some(edge)
            right = Some(edge)
            top = Some(edge)
            bottom = Some(edge)
          }
          "left" => left = Some(load_border(node, file~, context~))
          "right" => right = Some(load_border(node, file~, context~))
          "top" => top = Some(load_border(node, file~, context~))
          "bottom" => bottom = Some(load_border(node, file~, context~))
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in \{context} border (expected 'all', 'left', 'right', 'top', or 'bottom')",
            )
        }
      }
      { left, right, top, bottom }
    }
    _ =>
      raise schema_error(
        file~,
        "\{context} border must be a style name or a mapping",
      )
  }
}

///|
/// One border edge: a line-style name shorthand or a `{ style, color }` mapping.
fn load_border(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.Border raise @diag.SchemaError {
  match node {
    @yaml.Str(_) =>
      { style: load_border_style(node, file~, context~), color: None }
    @yaml.Map(entries) => {
      let mut style = None
      let mut color = None
      for entry in entries {
        let (key, node) = entry
        match key {
          "style" => style = Some(load_border_style(node, file~, context~))
          "color" =>
            color = Some(
              expect_color(node, file~, what="border 'color'", context~),
            )
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in \{context} border edge (expected 'style' or 'color')",
            )
        }
      }
      guard style is Some(style) else {
        raise schema_error(file~, "\{context} border needs a 'style'")
      }
      { style, color }
    }
    _ =>
      raise schema_error(
        file~,
        "\{context} border edge must be a style name or a mapping",
      )
  }
}

///|
fn load_border_style(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.BorderStyle raise @diag.SchemaError {
  match expect_string(node, file~, context="\{context} border style") {
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
        "\{context} has an unknown border style '\{other}' (expected 'thin', 'medium', 'thick', 'dashed', 'dotted', 'double', or 'hair')",
      )
  }
}
