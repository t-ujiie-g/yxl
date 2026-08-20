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
  cleared? : @model.StyleAttrs = @model.StyleAttrs::none(),
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
    // An inline style may still `extends:` a declared one; by now every
    // definition is resolved, so the base is a plain lookup.
    Some(node) =>
      load_style(node, file~, context~, find_base=name => {
        match defs.styles.get(name) {
          Some(style) => style
          None =>
            raise schema_error(
              file~,
              "\{context} extends undefined style '\{name}'",
            )
        }
      })
    None => @model.Style::empty()
  }
  let combined = match number_format {
    Some(code) => { ..base, number_format: Some(code) }
    None => base
  }
  // A value always wins over the same attribute cleared, whichever side said
  // which: the two states are exclusive, and `format:` beside the style is the
  // later word.
  let combined = {
    ..combined,
    cleared: combined.cleared.union(cleared).except(combined.assigned()),
  }
  if combined.is_empty() {
    None
  } else {
    Some(combined)
  }
}

///|
/// Parse a `style:` mapping into a model style. Keys are `font`, `fill`,
/// `border`, `align`, `protection`, `format`, and `extends`; anything else is a
/// diagnostic.
///
/// `format` belongs here as well as beside the style, because a number format is
/// part of a look — a "percent" style is a percent format and nothing else, and
/// without this it could be *declared* nowhere and would have to be repeated at
/// every cell that wore it, which is exactly the copying ADR-004 exists to stop.
/// A `format:` written beside the style still wins, as the caller layers it on.
///
/// `extends: <name>` names a style to inherit: `find_base` resolves the name (to
/// a declared definition), and everything this mapping sets is laid over it.
///
/// `null` is the third thing an attribute can say — that it is explicitly not
/// set, so neither an extended style nor a band supplies one (`docs/spec.md`
/// §6). A whole group written `null` clears every attribute in it.
fn load_style(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
  find_base~ : (String) -> @model.Style raise @diag.SchemaError,
) -> @model.Style raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="\{context} style")
  let mut font = None
  let mut fill = None
  let mut borders = None
  let mut align = None
  let mut protection = None
  let mut number_format = None
  let mut base = None
  let mut cleared = @model.StyleAttrs::none()
  for entry in entries {
    let (key, node) = entry
    match key {
      "font" => {
        let (loaded, group) = load_group(
          node,
          font_attrs,
          @model.Font::empty(),
          node => load_font(node, file~, context~),
        )
        font = loaded
        cleared = cleared.union(group)
      }
      "fill" =>
        match node {
          @yaml.Null => cleared = cleared.adding(Fill)
          _ => fill = Some(load_fill(node, file~, context~))
        }
      "border" => {
        let (loaded, group) = load_group(
          node,
          border_attrs,
          @model.Borders::empty(),
          node => load_borders(node, file~, context~),
        )
        borders = loaded
        cleared = cleared.union(group)
      }
      "align" => {
        let (loaded, group) = load_group(
          node,
          align_attrs,
          @model.Alignment::empty(),
          node => load_alignment(node, file~, context~),
        )
        align = loaded
        cleared = cleared.union(group)
      }
      "protection" => {
        let (loaded, group) = load_group(
          node,
          protection_attrs,
          @model.CellProtection::empty(),
          node => load_cell_protection(node, file~, context~),
        )
        protection = loaded
        cleared = cleared.union(group)
      }
      "format" =>
        match node {
          @yaml.Null => cleared = cleared.adding(NumberFormat)
          _ =>
            number_format = Some(
              expect_string(node, file~, context="\{context} style 'format'"),
            )
        }
      "extends" =>
        base = Some(
          find_base(expect_string(node, file~, context="\{context} 'extends'")),
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} style (expected 'font', 'fill', 'border', 'align', 'protection', 'format', or 'extends')",
        )
    }
  }
  let written : @model.Style = {
    font,
    fill,
    borders,
    align,
    number_format,
    protection,
    cleared: @model.StyleAttrs::none(),
  }
  // Setting an attribute wins over clearing it, whichever was written first:
  // `border: { all: thin, left: null }` has four edges, not three.
  let style = { ..written, cleared: cleared.except(written.assigned()) }
  match base {
    Some(base) => style.over(base)
    None => style
  }
}

///|
/// One group of a `style:` mapping — `font`, `border`, `align`, `protection`.
///
/// The group written `null` clears every attribute in it; otherwise it is
/// loaded, and a group that ends up setting nothing is dropped rather than kept
/// as an empty mapping.
fn[T : Eq] load_group(
  node : @yaml.Node,
  whole : @model.StyleAttrs,
  empty : T,
  load : (@yaml.Node) -> (T, @model.StyleAttrs) raise @diag.SchemaError,
) -> (T?, @model.StyleAttrs) raise @diag.SchemaError {
  guard !(node is @yaml.Null) else { return (None, whole) }
  let (loaded, cleared) = load(node)
  (if loaded == empty { None } else { Some(loaded) }, cleared)
}

///|
/// The attributes each group of the `style:` mapping holds, for the `null` that
/// clears a whole group at once.
let font_attrs : @model.StyleAttrs = @model.StyleAttrs::of([
  FontBold,
  FontItalic,
  FontUnderline,
  FontStrike,
  FontSize,
  FontName,
  FontColor,
])

///|
let align_attrs : @model.StyleAttrs = @model.StyleAttrs::of([
  AlignHorizontal,
  AlignVertical,
  AlignWrap,
])

///|
let border_attrs : @model.StyleAttrs = @model.StyleAttrs::of([
  BorderLeft,
  BorderRight,
  BorderTop,
  BorderBottom,
])

///|
let protection_attrs : @model.StyleAttrs = @model.StyleAttrs::of([
  ProtectionLocked,
  ProtectionHidden,
])

///|
fn load_font(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> (@model.Font, @model.StyleAttrs) raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="\{context} font")
  let mut bold = None
  let mut italic = None
  let mut underline = None
  let mut strike = None
  let mut size = None
  let mut name = None
  let mut color = None
  let mut cleared = @model.StyleAttrs::none()
  for entry in entries {
    let (key, node) = entry
    if node is @yaml.Null {
      cleared = cleared.adding(
        match key {
          "bold" => FontBold
          "italic" => FontItalic
          "underline" => FontUnderline
          "strike" => FontStrike
          "size" => FontSize
          "name" => FontName
          "color" => FontColor
          _ => raise unknown_font_key(key, file~, context~)
        },
      )
      continue
    }
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
      _ => raise unknown_font_key(key, file~, context~)
    }
  }
  ({ bold, italic, underline, strike, size, name, color }, cleared)
}

///|
fn unknown_font_key(
  key : String,
  file~ : String,
  context~ : String,
) -> @diag.SchemaError {
  schema_error(
    file~,
    "unknown key '\{key}' in \{context} font (expected 'bold', 'italic', 'underline', 'strike', 'size', 'name', or 'color')",
  )
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
) -> (@model.Alignment, @model.StyleAttrs) raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="\{context} align")
  let mut horizontal = None
  let mut vertical = None
  let mut wrap = None
  let mut cleared = @model.StyleAttrs::none()
  for entry in entries {
    let (key, node) = entry
    if node is @yaml.Null {
      cleared = cleared.adding(
        match key {
          "horizontal" => AlignHorizontal
          "vertical" => AlignVertical
          "wrap" => AlignWrap
          _ => raise unknown_align_key(key, file~, context~)
        },
      )
      continue
    }
    match key {
      "horizontal" => horizontal = Some(load_halign(node, file~, context~))
      "vertical" => vertical = Some(load_valign(node, file~, context~))
      "wrap" =>
        wrap = Some(expect_bool(node, file~, context="\{context} align 'wrap'"))
      _ => raise unknown_align_key(key, file~, context~)
    }
  }
  ({ horizontal, vertical, wrap }, cleared)
}

///|
fn unknown_align_key(
  key : String,
  file~ : String,
  context~ : String,
) -> @diag.SchemaError {
  schema_error(
    file~,
    "unknown key '\{key}' in \{context} align (expected 'horizontal', 'vertical', or 'wrap')",
  )
}

///|
/// The alignment and border-style spellings, each as one table serving both the
/// lookup and the diagnostic, so the two cannot drift apart.
let horizontal_alignments : Array[(String, @model.HAlign)] = [
  ("left", Left),
  ("center", Center),
  ("right", Right),
  ("fill", Fill),
  ("justify", Justify),
  ("distributed", Distributed),
]

///|
let vertical_alignments : Array[(String, @model.VAlign)] = [
  ("top", Top),
  ("middle", Middle),
  ("bottom", Bottom),
  ("justify", Justify),
  ("distributed", Distributed),
]

///|
let border_styles : Array[(String, @model.BorderStyle)] = [
  ("thin", Thin),
  ("medium", Medium),
  ("thick", Thick),
  ("dashed", Dashed),
  ("dotted", Dotted),
  ("double", Double),
  ("hair", Hair),
]

///|
fn load_halign(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.HAlign raise @diag.SchemaError {
  named(
    horizontal_alignments,
    expect_string(node, file~, context="\{context} horizontal align"),
    file~,
    what="horizontal alignment",
    context~,
  )
}

///|
fn load_valign(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.VAlign raise @diag.SchemaError {
  named(
    vertical_alignments,
    expect_string(node, file~, context="\{context} vertical align"),
    file~,
    what="vertical alignment",
    context~,
  )
}

///|
/// A `border` is a line-style shorthand (`border: thin`, all four sides) or a
/// mapping keyed by side (`all`, `left`, `right`, `top`, `bottom`).
fn load_borders(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> (@model.Borders, @model.StyleAttrs) raise @diag.SchemaError {
  match node {
    @yaml.Str(_) => {
      let edge = load_border(node, file~, context~)
      (
        {
          left: Some(edge),
          right: Some(edge),
          top: Some(edge),
          bottom: Some(edge),
        },
        @model.StyleAttrs::none(),
      )
    }
    @yaml.Map(entries) => {
      let mut left = None
      let mut right = None
      let mut top = None
      let mut bottom = None
      let mut cleared = @model.StyleAttrs::none()
      for entry in entries {
        let (key, node) = entry
        if node is @yaml.Null {
          if key == "all" {
            cleared = cleared.union(border_attrs)
            continue
          }
          cleared = cleared.adding(
            match key {
              "left" => BorderLeft
              "right" => BorderRight
              "top" => BorderTop
              "bottom" => BorderBottom
              _ => raise unknown_border_key(key, file~, context~)
            },
          )
          continue
        }
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
          _ => raise unknown_border_key(key, file~, context~)
        }
      }
      ({ left, right, top, bottom }, cleared)
    }
    _ =>
      raise schema_error(
        file~,
        "\{context} border must be a style name or a mapping",
      )
  }
}

///|
fn unknown_border_key(
  key : String,
  file~ : String,
  context~ : String,
) -> @diag.SchemaError {
  schema_error(
    file~,
    "unknown key '\{key}' in \{context} border (expected 'all', 'left', 'right', 'top', or 'bottom')",
  )
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
  named(
    border_styles,
    expect_string(node, file~, context="\{context} border style"),
    file~,
    what="border style",
    context~,
  )
}

///|
/// A style's `protection:` — what sheet protection does to a cell wearing it.
/// Neither key does anything until the sheet itself is protected.
fn load_cell_protection(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> (@model.CellProtection, @model.StyleAttrs) raise @diag.SchemaError {
  let what = "\{context} style 'protection'"
  let mut locked = None
  let mut hidden = None
  let mut cleared = @model.StyleAttrs::none()
  for entry in expect_map(node, file~, context=what) {
    let (key, value) = entry
    if value is @yaml.Null {
      cleared = cleared.adding(
        match key {
          "locked" => ProtectionLocked
          "hidden" => ProtectionHidden
          _ => raise unknown_protection_key(key, file~, what~)
        },
      )
      continue
    }
    match key {
      "locked" =>
        locked = Some(expect_bool(value, file~, context="\{what} 'locked'"))
      "hidden" =>
        hidden = Some(expect_bool(value, file~, context="\{what} 'hidden'"))
      _ => raise unknown_protection_key(key, file~, what~)
    }
  }
  guard locked is Some(_) || hidden is Some(_) || !cleared.is_empty() else {
    raise schema_error(
      file~,
      "\{what} sets nothing (expected 'locked' or 'hidden')",
    )
  }
  ({ locked, hidden }, cleared)
}

///|
fn unknown_protection_key(
  key : String,
  file~ : String,
  what~ : String,
) -> @diag.SchemaError {
  schema_error(
    file~,
    "unknown key '\{key}' in \{what} (expected 'locked' or 'hidden')",
  )
}
