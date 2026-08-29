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
    Some(code) => { ..base, number_format: Some(code), }
    None => base
  }
  let combined = combined.clearing(cleared)
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
/// An attribute or a whole group written `null` is cleared rather than set
/// (`docs/spec.md` §6).
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
  // `border: { all: thin, left: null }` has four edges, not three.
  let style = written.clearing(cleared)
  match base {
    Some(base) => style.over(base)
    None => style
  }
}

///|
/// One group of a `style:` mapping: what it sets, and what it clears — the whole
/// group written `null` clearing every attribute in it. A group that sets
/// nothing is dropped rather than kept as an empty mapping.
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
/// What each group of the `style:` mapping holds, for the `null` that clears the
/// group at once.
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
