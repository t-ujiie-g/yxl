///|
/// The three kinds, as Excel's "Sparklines" ribbon names them. One table
/// serves both the lookup and the diagnostic.
let sparkline_kinds : Array[(String, @model.SparklineKind)] = [
  ("line", Line),
  ("column", Column),
  ("win_loss", WinLoss),
]

///|
/// A sheet's `sparklines:` — a sequence of groups.
fn load_sparklines(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'sparklines'") {
    sheet.add_sparkline_group(load_sparkline_group(item, file~))
  }
}

///|
/// One `sparklines:` entry: `at`/`data` places a single sparkline, `cells:` a
/// group of them; everything else styles the whole group.
fn load_sparkline_group(
  node : @yaml.Node,
  file~ : String,
) -> @model.SparklineGroup raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a sparkline group")
  let context = match find_key(entries, "at") {
    Some(at_node) =>
      "sparkline at '\{expect_string(at_node, file~, context="sparkline 'at'")}'"
    None => "a sparkline group"
  }
  let mut at = None
  let mut data = None
  let cells : Array[@model.SparklineCell] = []
  let mut kind : @model.SparklineKind = Line
  let mut kind_written = None
  let mut markers = false
  let mut high = false
  let mut low = false
  let mut min = None
  let mut max = None
  let mut weight = None
  let mut color = None
  let mut markers_color = None
  let mut high_color = None
  let mut low_color = None
  let mut axis = false
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" =>
        at = Some(
          expect_cell_ref(
            expect_string(value, file~, context="sparkline 'at'"),
            file~,
            what="sparkline 'at'",
          ),
        )
      "data" =>
        data = Some(
          parse_sheet_range(
            expect_string(value, file~, context="\{context} 'data'"),
            file~,
            what="\{context} 'data'",
          ),
        )
      "cells" =>
        for item in expect_seq(value, file~, context="\{context} 'cells'") {
          cells.push(load_sparkline_cell(item, file~))
        }
      "type" => {
        let written = expect_string(value, file~, context="\{context} 'type'")
        kind = named(
          sparkline_kinds,
          written,
          file~,
          what="sparkline type",
          context~,
        )
        kind_written = Some(written)
      }
      "markers" =>
        markers = expect_bool(value, file~, context="\{context} 'markers'")
      "high" => high = expect_bool(value, file~, context="\{context} 'high'")
      "low" => low = expect_bool(value, file~, context="\{context} 'low'")
      "min" =>
        min = Some(expect_manual_bound(value, file~, what="\{context} 'min'"))
      "max" =>
        max = Some(expect_manual_bound(value, file~, what="\{context} 'max'"))
      "weight" => {
        let points = expect_number(value, file~, context="\{context} 'weight'")
        guard points > 0.0 else {
          raise schema_error(
            file~,
            "\{context} 'weight' must be above 0 (points), not \{points}",
          )
        }
        weight = Some(points)
      }
      "color" =>
        color = Some(expect_color(value, file~, what="'color'", context~))
      "colors" => {
        let (for_markers, for_high, for_low) = load_sparkline_colors(
          value,
          file~,
          context~,
        )
        markers_color = for_markers
        high_color = for_high
        low_color = for_low
      }
      "axis" => axis = expect_bool(value, file~, context="\{context} 'axis'")
      // Excel has these markers, but the backend's options carry them as
      // fields nothing can set — named here so the author gets the reason
      // rather than "unknown key" (ADR-006).
      "first" | "last" | "negative" =>
        raise schema_error(
          file~,
          "\{context} sets '\{key}', a marker the Excel backend cannot switch on yet — 'high', 'low', and 'markers' are available",
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'data', 'cells', 'type', 'markers', 'high', 'low', 'min', 'max', 'weight', 'color', 'colors', or 'axis')",
        )
    }
  }
  match (at, data, cells.is_empty()) {
    (Some(at), Some(data), true) => cells.push({ at, data })
    (Some(_), None, _) =>
      raise schema_error(file~, "\{context} is missing required key 'data'")
    (None, Some(_), _) =>
      raise schema_error(file~, "\{context} has 'data' but no 'at'")
    (Some(_), Some(_), false) =>
      raise schema_error(
        file~,
        "\{context} mixes 'at'/'data' with 'cells' — place the group one way",
      )
    (None, None, false) => ()
    (None, None, true) =>
      raise schema_error(
        file~,
        "a sparkline group places nothing (expected 'at' with 'data', or 'cells')",
      )
  }
  // Markers and weight belong to a line: the other kinds already draw one
  // mark per point, and Excel's own dialog greys both out.
  if kind is (Column | WinLoss) {
    let kind_name = kind_written.unwrap_or("column")
    if markers {
      raise schema_error(
        file~,
        "\{context} sets 'markers', which only a line sparkline draws (this one is '\{kind_name}')",
      )
    }
    if weight is Some(_) {
      raise schema_error(
        file~,
        "\{context} sets 'weight', which only a line sparkline has (this one is '\{kind_name}')",
      )
    }
  }
  if min is Some(min) && max is Some(max) && min > max {
    raise schema_error(file~, "\{context} has 'min' \{min} above 'max' \{max}")
  }
  {
    kind,
    cells,
    markers,
    high,
    low,
    min,
    max,
    weight,
    color,
    markers_color,
    high_color,
    low_color,
    axis,
  }
}

///|
/// One `cells:` entry: `{ at, data }` and nothing else.
fn load_sparkline_cell(
  node : @yaml.Node,
  file~ : String,
) -> @model.SparklineCell raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a sparkline 'cells' entry")
  let at = anchor_cell(
    entries,
    file~,
    subject="a sparkline 'cells' entry",
    noun="a sparkline cell",
  )
  let mut data = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "data" =>
        data = Some(
          parse_sheet_range(
            expect_string(value, file~, context="a sparkline cell 'data'"),
            file~,
            what="a sparkline cell 'data'",
          ),
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in a sparkline 'cells' entry (expected 'at' or 'data')",
        )
    }
  }
  guard data is Some(data) else {
    raise schema_error(
      file~,
      "a sparkline 'cells' entry is missing required key 'data'",
    )
  }
  { at, data }
}

///|
/// The `colors:` mapping — a colour per marker kind the backend can show.
fn load_sparkline_colors(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> (@units.Color?, @units.Color?, @units.Color?) raise @diag.SchemaError {
  let what = "\{context} 'colors'"
  let mut markers = None
  let mut high = None
  let mut low = None
  for entry in expect_map(node, file~, context=what) {
    let (key, value) = entry
    match key {
      "markers" =>
        markers = Some(
          expect_color(value, file~, what="'markers'", context=what),
        )
      "high" =>
        high = Some(expect_color(value, file~, what="'high'", context=what))
      "low" =>
        low = Some(expect_color(value, file~, what="'low'", context=what))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{what} (expected 'markers', 'high', or 'low')",
        )
    }
  }
  (markers, high, low)
}

///|
/// A manual bound: a whole number, because the backend accepts nothing finer.
fn expect_manual_bound(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
) -> Int raise @diag.SchemaError {
  guard node is @yaml.Int(bound) else {
    raise schema_error(
      file~,
      "\{what} must be a whole number (the Excel backend takes no finer bound)",
    )
  }
  bound.to_int()
}
