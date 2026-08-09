///|
/// A style used more than once is worth declaring; one used once is inlined at
/// its cell, where it reads as what it is.
const SHARED_AT_LEAST : Int = 2

///|
/// The names given to the styles a workbook shares, and the counts they were
/// chosen from. `declared` is in the order the styles will appear under
/// `defs.styles`.
priv struct StyleNames {
  declared : Array[(String, @model.Style)]
  by_style : Map[@model.Style, String]
}

///|
/// Work out which styles to declare, and what to call them.
fn StyleNames::of(wb : @model.Workbook) -> StyleNames {
  // Count every use, cells and bands alike: a look worn by one cell and one
  // column band is shared, and writing it twice would lose that.
  let counts : Map[@model.Style, Int] = Map([])
  fn count(style : @model.Style?) -> Unit {
    if style is Some(style) {
      counts[style] = counts.get(style).unwrap_or(0) + 1
    }
  }

  for sheet in wb.sheets {
    for cell in sheet.cells {
      count(cell.style)
    }
    for band in sheet.columns {
      count(band.style)
    }
    for band in sheet.rows {
      count(band.style)
    }
  }
  // Declaration order follows first appearance, so a reader meets `defs.styles`
  // in the order the sheets use it rather than in a hash order.
  let ordered : Array[@model.Style] = []
  let seen : @set.Set[@model.Style] = Set([])
  fn remember(style : @model.Style?) -> Unit {
    if style is Some(style) &&
      counts.get(style).unwrap_or(0) >= SHARED_AT_LEAST &&
      !seen.contains(style) {
      seen.add(style)
      ordered.push(style)
    }
  }

  for sheet in wb.sheets {
    for band in sheet.columns {
      remember(band.style)
    }
    for band in sheet.rows {
      remember(band.style)
    }
    for cell in sheet.cells {
      remember(cell.style)
    }
  }
  let taken : @set.Set[String] = Set([])
  let declared = []
  let by_style : Map[@model.Style, String] = Map([])
  for style in ordered {
    let name = unique(describe(style), taken)
    taken.add(name)
    declared.push((name, style))
    by_style[style] = name
  }
  { declared, by_style }
}

///|
/// How a cell should refer to `style`: by name where it was declared, inline
/// where it was not.
fn StyleNames::reference(self : StyleNames, style : @model.Style) -> @yaml.Node {
  match self.by_style.get(style) {
    Some(name) => @yaml.Str(name)
    None => style_node(style)
  }
}

///|
/// A cell's style split the way `docs/spec.md` §3 lays it out: the `style:`
/// reference, and the `format:` beside it.
///
/// A *declared* style keeps its number format inside it, because that is where
/// `defs.styles` puts one. Only an inline style — a look worn once, written at
/// its cell — has to hand the format out, and a look that is *nothing but* a
/// format leaves no style behind at all.
fn StyleNames::split(
  self : StyleNames,
  style : @model.Style?,
) -> (@yaml.Node?, String?) {
  guard style is Some(style) else { return (None, None) }
  if self.by_style.get(style) is Some(name) {
    return (Some(@yaml.Str(name)), None)
  }
  // A look worn once is written where it is worn, and a look that is *only* a
  // number format reads better as the bare `format:` shorthand than as a style
  // mapping with one key in it.
  let format = style.number_format
  let rest = { ..style, number_format: None }
  if rest.is_empty() {
    (None, format)
  } else {
    (Some(style_node(style)), None)
  }
}

///|
/// A name for a style, from the style itself.
///
/// Only a look with one unmistakable characteristic earns a word: a style whose
/// only distinguishing feature is a percentage format is `percent`, and one that
/// is bold on a dark fill is `header` — that pairing is what a heading is, and
/// no other kind of cell wears it. Everything else gets a number, because a name
/// that guesses wrong is worse than one that admits it knows nothing.
fn describe(style : @model.Style) -> String {
  if is_header(style) {
    return "header"
  }
  if style.number_format is Some(code) &&
    style.font is None &&
    style.fill is None &&
    style.borders is None {
    if named_format(code) is Some(name) {
      return name
    }
  }
  if style.fill is Some(_) &&
    style.font is None &&
    style.borders is None &&
    style.number_format is None {
    return "fill"
  }
  "style"
}

///|
/// Bold text on a solid fill: the one combination that means "heading" and
/// nothing else.
fn is_header(style : @model.Style) -> Bool {
  style.fill is Some(_) && style.font is Some(font) && font.bold is Some(true)
}

///|
/// The number formats common enough to have an ordinary English name. Anything
/// else is a code, and a name derived from a code would be a worse label than a
/// number.
fn named_format(code : String) -> String? {
  if code.contains("%") {
    return Some("percent")
  }
  if code.contains("$") || code.contains("¥") || code.contains("€") {
    return Some("currency")
  }
  if code.contains("y") && code.contains("d") {
    return Some("date")
  }
  if code.contains("#") || code.contains("0") {
    return Some("number")
  }
  None
}

///|
/// `base`, or `base_2`, `base_3`, … where the plain form is already taken.
fn unique(base : String, taken : @set.Set[String]) -> String {
  if !taken.contains(base) {
    return base
  }
  let mut suffix = 2
  while taken.contains("\{base}_\{suffix}") {
    suffix += 1
  }
  "\{base}_\{suffix}"
}

///|
/// A style as the `defs.styles` block writes it.
fn style(value : @model.Style) -> @yaml.Node {
  style_node(value)
}

///|
/// The mapping form of a style, used both under `defs.styles` and inline.
fn style_node(style : @model.Style) -> @yaml.Node {
  let entries = []
  if style.font is Some(font) {
    entries.push(("font", font_node(font)))
  }
  if style.fill is Some(fill) {
    entries.push(("fill", @yaml.Str(fill.color.hex())))
  }
  if style.borders is Some(borders) {
    entries.push(("border", borders_node(borders)))
  }
  if style.align is Some(align) {
    entries.push(("align", align_node(align)))
  }
  if style.protection is Some(protection) {
    let inner = []
    if protection.locked is Some(locked) {
      inner.push(("locked", @yaml.Bool(locked)))
    }
    if protection.hidden is Some(hidden) {
      inner.push(("hidden", @yaml.Bool(hidden)))
    }
    entries.push(("protection", @yaml.Map(inner)))
  }
  if style.number_format is Some(code) {
    entries.push(("format", @yaml.Str(code)))
  }
  @yaml.Map(entries)
}

///|
/// A font, with only the attributes it actually sets.
fn font_node(font : @model.Font) -> @yaml.Node {
  let entries = []
  if font.bold is Some(value) {
    entries.push(("bold", @yaml.Bool(value)))
  }
  if font.italic is Some(value) {
    entries.push(("italic", @yaml.Bool(value)))
  }
  if font.underline is Some(value) {
    entries.push(("underline", @yaml.Bool(value)))
  }
  if font.strike is Some(value) {
    entries.push(("strike", @yaml.Bool(value)))
  }
  if font.size is Some(value) {
    entries.push(("size", number(value)))
  }
  if font.name is Some(value) {
    entries.push(("name", @yaml.Str(value)))
  }
  if font.color is Some(color) {
    entries.push(("color", @yaml.Str(color.hex())))
  }
  @yaml.Map(entries)
}

///|
/// The borders, as the per-side mapping. The `border: thin` shorthand is left
/// for a person to apply — collapsing four equal edges into it would be right
/// more often than not, but "more often than not" is a guess.
fn borders_node(borders : @model.Borders) -> @yaml.Node {
  let entries = []
  fn side(name : String, edge : @model.Border?) -> Unit {
    if edge is Some(edge) {
      let inner = [("style", @yaml.Str(border_style_name(edge.style)))]
      if edge.color is Some(color) {
        inner.push(("color", @yaml.Str(color.hex())))
      }
      entries.push((name, @yaml.Map(inner)))
    }
  }

  side("left", borders.left)
  side("right", borders.right)
  side("top", borders.top)
  side("bottom", borders.bottom)
  @yaml.Map(entries)
}

///|
fn border_style_name(style : @model.BorderStyle) -> String {
  match style {
    Thin => "thin"
    Medium => "medium"
    Thick => "thick"
    Dashed => "dashed"
    Dotted => "dotted"
    Double => "double"
    Hair => "hair"
  }
}

///|
fn align_node(align : @model.Alignment) -> @yaml.Node {
  let entries = []
  if align.horizontal is Some(horizontal) {
    entries.push(
      (
        "horizontal",
        @yaml.Str(
          match horizontal {
            Left => "left"
            Center => "center"
            Right => "right"
            Fill => "fill"
            Justify => "justify"
            Distributed => "distributed"
          },
        ),
      ),
    )
  }
  if align.vertical is Some(vertical) {
    entries.push(
      (
        "vertical",
        @yaml.Str(
          match vertical {
            Top => "top"
            Middle => "middle"
            Bottom => "bottom"
            Justify => "justify"
            Distributed => "distributed"
          },
        ),
      ),
    )
  }
  if align.wrap is Some(wrap) {
    entries.push(("wrap", @yaml.Bool(wrap)))
  }
  @yaml.Map(entries)
}
