// Column- and row-style interpretation for the loader: turning a sheet's
// `columns:` / `rows:` sequences into whole-band default styles on the model
// sheet. Each entry selects a band with `at` — a column label (`B`, `D-F`) or a
// row number (`1`, `2-4`) — and carries a `{ style, format }` spec, reusing the
// shared style parser in `style.mbt`. (A sequence, not a mapping, because the
// YAML parser rejects bare integer keys, and row selectors are integers.)
// Structural loading lives in `loader.mbt`.

///|
/// Load a sheet's `columns:` sequence: each entry's `at` selects a column or
/// column range (`B`, `D-F`) styled by that entry's `{ style, format }` spec.
fn load_columns(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_seq(node, file~, context="'columns'") {
    let (selector, spec) = split_band(entry, file~, axis="column")
    let (first, last) = parse_column_selector(selector, file~)
    if load_axis_spec(spec, file~, context="column '\{selector}'")
      is Some(style) {
      sheet.set_column_style(first~, last~, style)
    }
  }
}

///|
/// Load a sheet's `rows:` sequence: each entry's `at` selects a row or row range
/// (`1`, `2-4`) styled by that entry's `{ style, format }` spec.
fn load_rows(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_seq(node, file~, context="'rows'") {
    let (selector, spec) = split_band(entry, file~, axis="row")
    let (first, last) = parse_row_selector(selector, file~)
    if load_axis_spec(spec, file~, context="row '\{selector}'") is Some(style) {
      sheet.set_row_style(first~, last~, style)
    }
  }
}

///|
/// Read the required `at` selector off a band entry, returning it alongside the
/// entry's full key list (`load_axis_spec` reads the remaining `style`/`format`
/// keys and skips `at`). A row `at` may be an integer; a column `at` is a label.
/// A missing `at` is a diagnostic.
fn split_band(
  node : @yaml.Node,
  file~ : String,
  axis~ : String,
) -> (String, Array[(String, @yaml.Node)]) raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a \{axis} entry")
  let mut selector = None
  for entry in entries {
    let (key, value) = entry
    if key == "at" {
      selector = Some(expect_selector(value, file~, axis~))
    }
  }
  guard selector is Some(selector) else {
    raise schema_error(file~, "a \{axis} entry is missing required key 'at'")
  }
  (selector, entries)
}

///|
/// A band selector: a string label, or (for rows) an integer rendered to its
/// digits. Rejects non-scalar selectors.
fn expect_selector(
  node : @yaml.Node,
  file~ : String,
  axis~ : String,
) -> String raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => text
    @yaml.Int(number) => number.to_string()
    _ => raise schema_error(file~, "a \{axis} 'at' must be text or a number")
  }
}

///|
/// A band spec: `at` (the already-consumed selector), plus optional `style`
/// and/or `format`, folded into a single style (an empty spec yields `None`, so
/// the band adds no style).
fn load_axis_spec(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  context~ : String,
) -> @model.Style? raise @diag.SchemaError {
  let mut style_node = None
  let mut format = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "at" => () // the selector, consumed by `split_band`
      "style" => style_node = Some(node)
      "format" =>
        format = Some(expect_string(node, file~, context="\{context} format"))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'style', or 'format')",
        )
    }
  }
  combine_style(style_node, format, file~, context~)
}

///|
/// Parse a column selector into an inclusive 1-based range: `B` -> (2, 2),
/// `D-F` -> (4, 6). A reversed range (`F-D`) is a diagnostic.
fn parse_column_selector(
  selector : String,
  file~ : String,
) -> (Int, Int) raise @diag.SchemaError {
  let (start, end) = split_range(selector)
  guard @units.parse_column(start) is Some(first) else {
    raise schema_error(file~, "'\{selector}' is not a valid column")
  }
  let last = match end {
    Some(end) =>
      match @units.parse_column(end) {
        Some(last) => last
        None => raise schema_error(file~, "'\{selector}' is not a valid column")
      }
    None => first
  }
  guard first <= last else {
    raise schema_error(file~, "column range '\{selector}' is reversed")
  }
  (first, last)
}

///|
/// Parse a row selector into an inclusive 1-based range: `1` -> (1, 1),
/// `2-4` -> (2, 4). A reversed range (`4-2`) is a diagnostic.
fn parse_row_selector(
  selector : String,
  file~ : String,
) -> (Int, Int) raise @diag.SchemaError {
  let (start, end) = split_range(selector)
  guard parse_row_index(start) is Some(first) else {
    raise schema_error(file~, "'\{selector}' is not a valid row")
  }
  let last = match end {
    Some(end) =>
      match parse_row_index(end) {
        Some(last) => last
        None => raise schema_error(file~, "'\{selector}' is not a valid row")
      }
    None => first
  }
  guard first <= last else {
    raise schema_error(file~, "row range '\{selector}' is reversed")
  }
  (first, last)
}

///|
/// Split a `start-end` range selector on its single `-`; a bare selector has no
/// end. `A` -> `("A", None)`, `D-F` -> `("D", Some("F"))`.
fn split_range(selector : String) -> (String, String?) {
  match selector.find("-") {
    Some(index) =>
      (selector[0:index].to_owned(), Some(selector[index + 1:].to_owned()))
    None => (selector, None)
  }
}

///|
/// Parse a run of ASCII digits as a 1-based row index (`>= 1`), or `None`. A row
/// number is a positive integer, so `0` is rejected.
fn parse_row_index(text : String) -> Int? {
  match @units.parse_uint(text[:]) {
    Some(value) if value >= 1 => Some(value)
    _ => None
  }
}
