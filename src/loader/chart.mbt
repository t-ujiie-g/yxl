///|
/// The chart kinds a spec may name, and what each means. One table serves both
/// the lookup and the diagnostic, so the two cannot drift apart.
let chart_kinds : Array[(String, @model.ChartKind)] = [
  ("column", Column),
  ("column_stacked", ColumnStacked),
  ("column_percent_stacked", ColumnPercentStacked),
  ("bar", Bar),
  ("bar_stacked", BarStacked),
  ("bar_percent_stacked", BarPercentStacked),
  ("line", Line),
  ("area", Area),
  ("area_stacked", AreaStacked),
  ("area_percent_stacked", AreaPercentStacked),
  ("pie", Pie),
  ("doughnut", Doughnut),
  ("scatter", Scatter),
  ("radar", Radar),
]

///|
/// Where a legend may sit. `none` leaves the chart without one.
let legend_positions : Array[(String, @model.LegendPosition)] = [
  ("bottom", Bottom),
  ("top", Top),
  ("left", Left),
  ("right", Right),
  ("top_right", TopRight),
  ("none", NoLegend),
]

///|
/// A sheet's `charts:` — a sequence of charts, each anchored at a cell.
fn load_charts(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'charts'") {
    sheet.add_chart(load_chart(item, file~))
  }
}

///|
/// One `charts:` entry: where it sits, what kind it is, what it plots, and the
/// trimmings — title, legend, size, and the two axes.
fn load_chart(
  node : @yaml.Node,
  file~ : String,
) -> @model.Chart raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a chart")
  let at = anchor_cell(entries, file~, subject="a chart", noun="chart")
  let context = "chart at '\{at.to_a1()}'"
  let mut kind = None
  let mut series = None
  let mut title = None
  let mut legend = None
  let mut size = None
  let mut x_axis = None
  let mut y_axis = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "type" =>
        kind = Some(
          named(
            chart_kinds,
            expect_string(value, file~, context="\{context} 'type'"),
            file~,
            what="chart type",
            context~,
          ),
        )
      "series" => series = Some(load_series(value, file~, context~))
      "title" =>
        title = Some(expect_string(value, file~, context="\{context} 'title'"))
      "legend" =>
        legend = Some(
          named(
            legend_positions,
            expect_string(value, file~, context="\{context} 'legend'"),
            file~,
            what="legend position",
            context~,
          ),
        )
      "size" => size = Some(load_chart_size(value, file~, context~))
      "x_axis" | "y_axis" => {
        let axis = load_chart_axis(value, file~, context="\{context} '\{key}'")
        if key == "x_axis" {
          x_axis = Some(axis)
        } else {
          y_axis = Some(axis)
        }
      }
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'type', 'series', 'title', 'legend', 'size', 'x_axis', or 'y_axis')",
        )
    }
  }
  guard kind is Some(kind) else {
    raise schema_error(file~, "\{context} is missing required key 'type'")
  }
  guard series is Some(series) else {
    raise schema_error(file~, "\{context} is missing required key 'series'")
  }
  { at, kind, series, title, legend, size, x_axis, y_axis }
}

///|
/// A chart's `series:` — what it plots, in the order the legend lists it.
fn load_series(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Array[@model.ChartSeries] raise @diag.SchemaError {
  let series = []
  for item in expect_seq(node, file~, context="\{context} 'series'") {
    series.push(load_one_series(item, file~, context~))
  }
  // Excel draws nothing for a chart with no series, and says nothing about why.
  guard !series.is_empty() else {
    raise schema_error(
      file~,
      "\{context} 'series' is empty; a chart plots at least one",
    )
  }
  series
}

///|
/// One series: the values it plots, optionally what to label them and what to
/// call the series itself.
fn load_one_series(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ChartSeries raise @diag.SchemaError {
  let what = "\{context} series"
  let mut values = None
  let mut categories = None
  let mut name : @model.SeriesName? = None
  for entry in expect_map(node, file~, context=what) {
    let (key, value) = entry
    match key {
      "values" | "categories" => {
        let range = parse_sheet_range(
          expect_string(value, file~, context="\{what} '\{key}'"),
          file~,
          what="\{what} '\{key}'",
        )
        if key == "values" {
          values = Some(range)
        } else {
          categories = Some(range)
        }
      }
      "name" | "name_from" => {
        guard name is None else {
          raise schema_error(
            file~,
            "\{what} sets both 'name' and 'name_from'; a series is called one thing",
          )
        }
        let text = expect_string(value, file~, context="\{what} '\{key}'")
        name = Some(
          if key == "name" {
            // The backend reads a name holding '!' as a reference to a cell, so
            // a literal that looks like one would silently become a lookup.
            guard !text.contains("!") else {
              raise schema_error(
                file~,
                "\{what} 'name' '\{text}' looks like a cell reference; use 'name_from' to read the name from a cell",
              )
            }
            @model.Literal(text)
          } else {
            let (sheet, reference) = split_sheet_prefix(
              text,
              file~,
              what="\{what} 'name_from'",
            )
            FromCell(
              sheet~,
              at=expect_cell_ref(reference, file~, what="\{what} 'name_from'"),
            )
          },
        )
      }
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{what} (expected 'values', 'categories', 'name', or 'name_from')",
        )
    }
  }
  guard values is Some(values) else {
    raise schema_error(file~, "\{what} is missing required key 'values'")
  }
  { values, categories, name }
}

///|
/// A chart's `size:` — width and height in pixels, both required and both
/// positive.
fn load_chart_size(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ChartSize raise @diag.SchemaError {
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
  { width, height }
}

///|
/// One of a chart's axes: what to call it, and where to pin its ends.
fn load_chart_axis(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ChartAxis raise @diag.SchemaError {
  let mut title = None
  let mut min = None
  let mut max = None
  for entry in expect_map(node, file~, context~) {
    let (key, value) = entry
    match key {
      "title" =>
        title = Some(expect_string(value, file~, context="\{context} 'title'"))
      "min" =>
        min = Some(expect_number(value, file~, context="\{context} 'min'"))
      "max" =>
        max = Some(expect_number(value, file~, context="\{context} 'max'"))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'title', 'min', or 'max')",
        )
    }
  }
  guard !(title is None && min is None && max is None) else {
    raise schema_error(
      file~,
      "\{context} sets nothing (expected 'title', 'min', or 'max')",
    )
  }
  if min is Some(low) && max is Some(high) && low >= high {
    raise schema_error(
      file~,
      "\{context} has 'min' \{low} at or above 'max' \{high}",
    )
  }
  { title, min, max }
}
