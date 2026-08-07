// Rendering a sheet's `charts:` block — `docs/spec.md` §12, the inverse of the
// loader's chart reading.
//
// The reader has already refused whatever it could not name confidently, so
// nothing here decides what survives. What is decided here is only how it
// reads, under the same rule as the rest of `render`: a value equal to the
// schema's own default is left unsaid.

///|
/// A sheet's `charts:` block.
fn charts(sheet : @model.Sheet) -> @yaml.Node {
  let rendered = []
  for chart in sheet.charts {
    let entries = [
      ("at", @yaml.Str(chart.at.to_a1())),
      ("type", @yaml.Str(chart_type(chart.kind))),
    ]
    if chart.title is Some(title) {
      entries.push(("title", @yaml.Str(title)))
    }
    if chart.legend is Some(position) {
      entries.push(("legend", @yaml.Str(legend_position(position))))
    }
    if chart.size is Some({ width, height }) {
      if size(width=Some(width), height=Some(height)) is Some(node) {
        entries.push(("size", node))
      }
    }
    if chart.x_axis is Some(axis) {
      entries.push(("x_axis", chart_axis(axis)))
    }
    if chart.y_axis is Some(axis) {
      entries.push(("y_axis", chart_axis(axis)))
    }
    // Last, and deliberately: `series` is the long part, and a reader scanning
    // the block wants the chart's identity above it.
    entries.push(("series", chart_series(chart.series)))
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}

///|
/// The plotted series, in the order the legend lists them.
fn chart_series(series : Array[@model.ChartSeries]) -> @yaml.Node {
  let rendered = []
  for entry in series {
    let fields = [("values", @yaml.Str(sheet_range(entry.values)))]
    if entry.categories is Some(categories) {
      fields.push(("categories", @yaml.Str(sheet_range(categories))))
    }
    match entry.name {
      Some(Literal(text)) => fields.push(("name", @yaml.Str(text)))
      Some(FromCell(sheet~, at~)) =>
        fields.push(
          (
            "name_from",
            @yaml.Str(
              match sheet {
                Some(name) => "\{name}!\{at.to_a1()}"
                None => at.to_a1()
              },
            ),
          ),
        )
      None => ()
    }
    rendered.push(@yaml.Map(fields))
  }
  @yaml.Seq(rendered)
}

///|
/// One axis. The schema wants at least one of the three, which the reader
/// guarantees by building no axis at all from an empty one.
fn chart_axis(axis : @model.ChartAxis) -> @yaml.Node {
  let entries = []
  if axis.title is Some(title) {
    entries.push(("title", @yaml.Str(title)))
  }
  if axis.min is Some(min) {
    entries.push(("min", number(min)))
  }
  if axis.max is Some(max) {
    entries.push(("max", number(max)))
  }
  @yaml.Map(entries)
}

///|
/// The bareword the schema names a kind by.
fn chart_type(kind : @model.ChartKind) -> String {
  match kind {
    Column => "column"
    ColumnStacked => "column_stacked"
    ColumnPercentStacked => "column_percent_stacked"
    Bar => "bar"
    BarStacked => "bar_stacked"
    BarPercentStacked => "bar_percent_stacked"
    Line => "line"
    Area => "area"
    AreaStacked => "area_stacked"
    AreaPercentStacked => "area_percent_stacked"
    Pie => "pie"
    Doughnut => "doughnut"
    Scatter => "scatter"
    Radar => "radar"
  }
}

///|
/// Where the legend sits, as the schema spells it.
fn legend_position(position : @model.LegendPosition) -> String {
  match position {
    Bottom => "bottom"
    Top => "top"
    Left => "left"
    Right => "right"
    TopRight => "top_right"
    NoLegend => "none"
  }
}
