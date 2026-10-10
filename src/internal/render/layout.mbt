///|
/// A sheet's bands. `down` picks the vocabulary — a row band's size is a
/// `height` in points and its span a number, where a column's is a `width` in
/// character units and its span a letter.
fn bands(
  bands : Array[@model.AxisBand],
  styles : StyleNames,
  down~ : Bool,
) -> @yaml.Node {
  let rendered = []
  for band in bands {
    let entries = [("at", @yaml.Str(span(band, down~)))]
    if band.size is Some(size) {
      entries.push((if down { "height" } else { "width" }, number(size)))
    }
    if band.style is Some(style) {
      entries.push(("style", styles.reference(style)))
    }
    if band.hidden is Some(hidden) {
      entries.push(("hidden", @yaml.Bool(hidden)))
    }
    if band.outline_level is Some(level) {
      entries.push(("group", @yaml.Int(level.to_int64())))
    }
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}

///|
/// A band's `at`: one label, or `first-last` where it covers a span.
fn span(band : @model.AxisBand, down~ : Bool) -> String {
  let first = if down {
    band.first.to_string()
  } else {
    column_label(band.first)
  }
  if band.first == band.last {
    return first
  }
  let last = if down { band.last.to_string() } else { column_label(band.last) }
  "\{first}-\{last}"
}

///|
/// A 1-based column index as its Excel letters. `units` renders a whole cell
/// reference; a band's `at` is the column alone, so the row is dropped from a
/// reference in row 1 rather than repeating the base-26 arithmetic here.
fn column_label(col : Int) -> String {
  let reference = @units.CellRef(col~, row=1).to_a1()
  reference[:reference.length() - 1].to_owned()
}

///|
/// A sheet's `print:` block, with only the keys the setup actually sets.
fn print_setup(page : @model.PageSetup) -> @yaml.Node {
  let entries = []
  if page.area is Some(area) {
    entries.push(("area", @yaml.Str(area.to_a1())))
  }
  if page.orientation is Some(orientation) {
    entries.push(
      (
        "orientation",
        @yaml.Str(
          match orientation {
            Portrait => "portrait"
            Landscape => "landscape"
          },
        ),
      ),
    )
  }
  match page.scale {
    Some(Percent(percent)) =>
      entries.push(("scale", @yaml.Int(percent.to_int64())))
    Some(Fit(width~, height~)) => {
      let fit = []
      // Zero means "leave this axis alone", which the spec says by omission.
      if width > 0 {
        fit.push(("width", @yaml.Int(width.to_int64())))
      }
      if height > 0 {
        fit.push(("height", @yaml.Int(height.to_int64())))
      }
      if !fit.is_empty() {
        entries.push(("fit", @yaml.Map(fit)))
      }
    }
    None => ()
  }
  if page.margins is Some(margins) {
    let inner = []
    fn margin(name : String, value : Double?) -> Unit {
      if value is Some(value) {
        inner.push((name, number(value)))
      }
    }

    margin("top", margins.top)
    margin("bottom", margins.bottom)
    margin("left", margins.left)
    margin("right", margins.right)
    margin("header", margins.header)
    margin("footer", margins.footer)
    if !inner.is_empty() {
      entries.push(("margins", @yaml.Map(inner)))
    }
  }
  if page.header is Some(header) {
    entries.push(("header", @yaml.Str(header)))
  }
  if page.footer is Some(footer) {
    entries.push(("footer", @yaml.Str(footer)))
  }
  if !page.breaks.is_empty() {
    let cells = []
    for at in page.breaks {
      cells.push(@yaml.Str(at.to_a1()))
    }
    entries.push(("breaks", @yaml.Seq(cells)))
  }
  @yaml.Map(entries)
}
