///|
/// The chart part's own namespace, and DrawingML's, which its text runs are in
/// (ECMA-376 §14.2.1, §20.1).
const CHART_NS : String = "http://schemas.openxmlformats.org/drawingml/2006/chart"

///|
const DRAWING_NS : String = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
/// EMU per pixel at the 96 dpi Excel positions drawings against: the file
/// records a chart's size in EMU and the spec names it in pixels.
const EMU_PER_PIXEL : Int = 9525

///|
/// The size the backend gives a chart that named none. Recovering it would put
/// an explicit `size:` on every extracted chart, saying what the default
/// already says.
const DEFAULT_CHART_WIDTH : Int = 480

///|
const DEFAULT_CHART_HEIGHT : Int = 260

///|
/// The charts on a sheet.
fn read_charts(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit {
  guard backend.sheet(sheet.name) is Some(source) else { return }
  for chart in source.charts() {
    if read_chart(chart, sheet.name, notes) is Some(recovered) {
      sheet.add_chart(recovered)
    }
  }
}

///|
/// One chart, or `None` with the reason already reported.
fn read_chart(
  chart : @xlsx.Chart,
  sheet_name : String,
  notes : Notes,
) -> @model.Chart? {
  let context = "the chart at '\{chart.reference}' on '\{sheet_name}'"
  guard @units.CellRef::parse_a1(chart.reference) is Some(at) else {
    notes.drop("\{context}, which is anchored somewhere the spec cannot name")
    return None
  }
  guard parse_xml(chart.xml) is Some(root) &&
    root.child(CHART_NS, "chart") is Some(body) &&
    body.child(CHART_NS, "plotArea") is Some(plot) else {
    notes.drop("\{context}, whose part is not a chart this reader can follow")
    return None
  }
  // A plot area may hold several chart groups — that is how Excel builds a
  // combination chart, bars with a line over them. A spec names one type per
  // chart, so reading the first group would silently drop the others.
  let groups = plot.children.filter(child => {
    child.ns == CHART_NS && child.name.has_suffix("Chart")
  })
  guard groups.length() == 1 else {
    notes.drop(
      if groups.is_empty() {
        "\{context}, whose plot area holds no chart type this reader recognizes"
      } else {
        "\{context}, which combines \{groups.length()} chart types in one plot area — a spec declares one type per chart"
      },
    )
    return None
  }
  let group = groups[0]
  guard chart_kind(group) is Some(kind) else {
    notes.drop(
      "\{context}, which is a '\{group.name}' — a kind the spec has no word for",
    )
    return None
  }
  guard read_series(group, kind, context, notes) is Some(series) else {
    return None
  }
  guard !series.is_empty() else {
    notes.drop("\{context}, which plots no series")
    return None
  }
  let (x_axis, y_axis) = read_axes(group, plot)
  Some({
    at,
    kind,
    series,
    title: read_title(body, context, notes),
    legend: read_legend(body, context, notes),
    size: read_size(chart),
    x_axis,
    y_axis,
  })
}

///|
/// The chart group's element name, plus the two attributes that decide what a
/// bar or an area chart actually is, as one of the kinds the spec names.
///
/// A grouping with no word in the schema — a stacked *line* chart, say — is
/// `None` rather than the nearest kind: "line" would plot the same ranges a
/// different way, which is exactly the confident wrong answer to avoid.
fn chart_kind(group : XmlElement) -> @model.ChartKind? {
  let grouping = attribute_of(group, "grouping").unwrap_or("standard")
  match group.name {
    "barChart" => {
      let direction = attribute_of(group, "barDir").unwrap_or("col")
      match (direction, grouping) {
        ("col", "clustered" | "standard") => Some(Column)
        ("col", "stacked") => Some(ColumnStacked)
        ("col", "percentStacked") => Some(ColumnPercentStacked)
        ("bar", "clustered" | "standard") => Some(Bar)
        ("bar", "stacked") => Some(BarStacked)
        ("bar", "percentStacked") => Some(BarPercentStacked)
        _ => None
      }
    }
    "areaChart" =>
      match grouping {
        "standard" => Some(Area)
        "stacked" => Some(AreaStacked)
        "percentStacked" => Some(AreaPercentStacked)
        _ => None
      }
    "lineChart" => if grouping == "standard" { Some(Line) } else { None }
    "pieChart" => Some(Pie)
    "doughnutChart" => Some(Doughnut)
    "scatterChart" => Some(Scatter)
    "radarChart" => Some(Radar)
    _ => None
  }
}

///|
/// Every series in the group, or `None` with the reason reported — one series
/// this reader cannot follow fails the whole chart, because a chart missing a
/// series is a different chart, not a lesser one.
fn read_series(
  group : XmlElement,
  kind : @model.ChartKind,
  context : String,
  notes : Notes,
) -> Array[@model.ChartSeries]? {
  // A scatter chart plots X against Y and spells its two ranges accordingly;
  // every other kind labels a value with a category.
  let (categories_tag, values_tag) = if kind is Scatter {
    ("xVal", "yVal")
  } else {
    ("cat", "val")
  }
  let recovered = []
  for series in group.children_named(CHART_NS, "ser") {
    guard series.child(CHART_NS, values_tag) is Some(values_element) else {
      notes.drop("\{context}, one of whose series plots no range")
      return None
    }
    guard reference_in(values_element) is Some(formula) &&
      parse_sheet_range(formula) is Some(values) else {
      notes.drop(
        "\{context}, one of whose series holds its values outright rather than pointing at cells",
      )
      return None
    }
    let categories = match series.child(CHART_NS, categories_tag) {
      Some(element) =>
        match reference_in(element) {
          Some(formula) => parse_sheet_range(formula)
          None => None
        }
      None => None
    }
    let entry : @model.ChartSeries = {
      values,
      categories,
      name: series_name(series, notes),
    }
    recovered.push(entry)
  }
  Some(recovered)
}

///|
/// What the legend calls a series: a cell to read it from, or the words
/// themselves.
fn series_name(series : XmlElement, notes : Notes) -> @model.SeriesName? {
  guard series.child(CHART_NS, "tx") is Some(tx) else { return None }
  if reference_in(tx) is Some(formula) {
    guard parse_sheet_range(formula) is Some(source) else { return None }
    // A name is read from one cell. A reference spanning more is not something
    // the schema can ask for, and picking a corner of it would be a guess.
    guard source.range.top_left == source.range.bottom_right else {
      notes.drop(
        "a series name read from '\{formula}', which is a range rather than a cell",
      )
      return None
    }
    return Some(FromCell(sheet=source.sheet, at=source.range.top_left))
  }
  guard tx.child(CHART_NS, "v") is Some(literal) else { return None }
  // Excel reads a series name holding '!' as a reference, so the loader
  // refuses one — and `render` must emit only what the loader accepts.
  guard !literal.text.contains("!") else {
    notes.drop(
      "a series named '\{literal.text}', which holds a '!' the spec cannot write literally",
    )
    return None
  }
  Some(Literal(literal.text))
}

///|
/// The `<c:f>` inside whichever kind of reference this element wraps. Looked up
/// as a direct child so that a data label's own reference, nested deeper, is
/// never mistaken for the series'.
fn reference_in(element : XmlElement) -> String? {
  for kind in ["numRef", "strRef", "multiLvlStrRef"] {
    if element.child(CHART_NS, kind) is Some(wrapper) &&
      wrapper.child(CHART_NS, "f") is Some(formula) {
      return Some(formula.text)
    }
  }
  None
}

///|
/// The chart's own title — the one above the plot, not an axis'.
fn read_title(body : XmlElement, context : String, notes : Notes) -> String? {
  guard body.child(CHART_NS, "title") is Some(title) else { return None }
  // A title may be read from a cell instead of written out. The spec carries
  // words, so recovering the formula as the title would put the reference on
  // the chart as literal text.
  if reference_in_title(title) is Some(formula) {
    notes.drop(
      "\{context}, whose title is read from '\{formula}' — the spec carries a title as text",
    )
    return None
  }
  text_of(title)
}

///|
/// Whether a title takes its words from cells, and from where.
fn reference_in_title(title : XmlElement) -> String? {
  guard title.child(CHART_NS, "tx") is Some(tx) else { return None }
  reference_in(tx)
}

///|
/// Where the legend sits. No `<c:legend>` at all is a chart drawn without one,
/// which the spec says as `none`; a legend that names no position keeps Excel's
/// own default, which the spec says by staying quiet.
fn read_legend(
  body : XmlElement,
  context : String,
  notes : Notes,
) -> @model.LegendPosition? {
  guard body.child(CHART_NS, "legend") is Some(legend) else {
    return Some(NoLegend)
  }
  guard attribute_of(legend, "legendPos") is Some(position) else { return None }
  match position {
    "b" => Some(Bottom)
    "t" => Some(Top)
    "l" => Some(Left)
    "r" => Some(Right)
    "tr" => Some(TopRight)
    other => {
      notes.drop(
        "\{context}, whose legend sits at '\{other}' — a place the spec has no word for",
      )
      None
    }
  }
}

///|
/// The category and value axes, matched to the chart group by the ids it lists
/// rather than by their order in the plot area — a chart with a secondary axis
/// has four of them, and position says nothing about which pair is this
/// group's. A pie lists none, and gets none.
fn read_axes(
  group : XmlElement,
  plot : XmlElement,
) -> (@model.ChartAxis?, @model.ChartAxis?) {
  let ids = group
    .children_named(CHART_NS, "axId")
    .filter_map(element => element.attribute("val"))
  fn axis(index : Int) -> @model.ChartAxis? {
    guard index < ids.length() else { return None }
    for candidate in plot.children {
      guard candidate.ns == CHART_NS && candidate.name.has_suffix("Ax") else {
        continue
      }
      if attribute_of(candidate, "axId") == Some(ids[index]) {
        return read_axis(candidate)
      }
    }
    None
  }

  // ECMA-376 §21.2.2.9: a group lists its axis ids category-first.
  (axis(0), axis(1))
}

///|
/// One axis, or `None` when it says nothing the spec can carry. The schema
/// wants at least one of title, min and max on an `x_axis:`, so an axis with
/// none of them must not be written at all — an empty mapping is a spec the
/// loader refuses.
fn read_axis(element : XmlElement) -> @model.ChartAxis? {
  let title = match element.child(CHART_NS, "title") {
    Some(node) => text_of(node)
    None => None
  }
  let scaling = element.child(CHART_NS, "scaling")
  let min = bound(scaling, "min")
  let max = bound(scaling, "max")
  guard title is Some(_) || min is Some(_) || max is Some(_) else {
    return None
  }
  Some({ title, min, max, })
}

///|
/// One end of an axis' manual scale.
fn bound(scaling : XmlElement?, name : String) -> Double? {
  guard scaling is Some(element) else { return None }
  guard attribute_of(element, name) is Some(text) else { return None }
  try @string.parse_double(text) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
/// The chart's size in pixels, when it is not the size the backend gives one
/// that asked for none.
fn read_size(chart : @xlsx.Chart) -> @model.ChartSize? {
  let width = chart.width_emu / EMU_PER_PIXEL
  let height = chart.height_emu / EMU_PER_PIXEL
  guard width > 0 && height > 0 else { return None }
  guard width != DEFAULT_CHART_WIDTH || height != DEFAULT_CHART_HEIGHT else {
    return None
  }
  Some({ width, height, })
}

///|
/// The `val` of a named child — the shape almost every setting in a chart part
/// takes.
fn attribute_of(element : XmlElement, name : String) -> String? {
  guard element.child(CHART_NS, name) is Some(child) else { return None }
  child.attribute("val")
}

///|
/// The words inside a title, gathered from its DrawingML runs. Several runs are
/// one title — Excel splits one wherever its formatting changes — so they are
/// joined rather than the first one taken.
fn text_of(title : XmlElement) -> String? {
  let runs = title.descendants(DRAWING_NS, "t")
  guard !runs.is_empty() else { return None }
  let text = StringBuilder()
  for run in runs {
    text.write_string(run.text)
  }
  let joined = text.to_string()
  if joined.is_empty() {
    None
  } else {
    Some(joined)
  }
}
