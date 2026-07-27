// Column- and row-band interpretation for the loader: turning a sheet's
// `columns:` / `rows:` sequences into `@model.AxisBand`s on the model sheet.
// Each entry selects a band with `at` — a column label (`B`, `D-F`) or a row
// number (`1`, `2-4`) — and carries a `{ style, format, width|height, hidden,
// group }` spec, reusing the shared style parser in `style.mbt`. (A sequence,
// not a mapping, because the YAML parser rejects bare integer keys, and row
// selectors are integers.) Structural loading lives in `loader.mbt`.

///|
/// Load a sheet's `columns:` sequence: each entry's `at` selects a column or
/// column range (`B`, `D-F`) carrying that entry's band spec, whose size key is
/// `width` (in character units).
fn load_columns(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  for entry in expect_seq(node, file~, context="'columns'") {
    let (selector, spec) = split_band(entry, file~, axis="column")
    let (first, last) = parse_column_selector(selector, file~)
    let band = load_axis_spec(
      spec,
      file~,
      defs~,
      size_key="width",
      context="column '\{selector}'",
    )
    if !band.is_empty() {
      sheet.set_column_band(
        first~,
        last~,
        style?=band.style,
        width?=band.size,
        hidden?=band.hidden,
        outline_level?=band.outline_level,
      )
    }
  }
}

///|
/// Load a sheet's `rows:` sequence: each entry's `at` selects a row or row range
/// (`1`, `2-4`) carrying that entry's band spec, whose size key is `height` (in
/// points).
fn load_rows(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  for entry in expect_seq(node, file~, context="'rows'") {
    let (selector, spec) = split_band(entry, file~, axis="row")
    let (first, last) = parse_row_selector(selector, file~)
    let band = load_axis_spec(
      spec,
      file~,
      defs~,
      size_key="height",
      context="row '\{selector}'",
    )
    if !band.is_empty() {
      sheet.set_row_band(
        first~,
        last~,
        style?=band.style,
        height?=band.size,
        hidden?=band.hidden,
        outline_level?=band.outline_level,
      )
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
/// What a band entry sets, before the selector is resolved to a span: the folded
/// style, the size (a `width` or a `height`), the hidden flag, and the outline
/// level. Each is `None` when the entry leaves it out.
priv struct AxisSpec {
  style : @model.Style?
  size : Double?
  hidden : Bool?
  outline_level : Int?
}

///|
/// Whether the entry set nothing at all (`- at: B` on its own), in which case it
/// contributes no band rather than an all-defaults one.
fn AxisSpec::is_empty(self : AxisSpec) -> Bool {
  self.style is None &&
  self.size is None &&
  self.hidden is None &&
  self.outline_level is None
}

///|
/// A band spec: `at` (the already-consumed selector), plus optional `style`,
/// `format`, a size (`width` for columns, `height` for rows — `size_key` names
/// which), `hidden`, and `group` (the outline level).
fn load_axis_spec(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  defs~ : Defs,
  size_key~ : String,
  context~ : String,
) -> AxisSpec raise @diag.SchemaError {
  let mut style_node = None
  let mut format = None
  let mut size = None
  let mut hidden = None
  let mut outline_level = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "at" => () // the selector, consumed by `split_band`
      "style" => style_node = Some(node)
      "format" =>
        format = Some(expect_string(node, file~, context="\{context} format"))
      "hidden" =>
        hidden = Some(expect_bool(node, file~, context="\{context} hidden"))
      "group" =>
        outline_level = Some(expect_outline_level(node, file~, context~))
      _ if key == size_key =>
        size = Some(
          expect_number(node, file~, context="\{context} \{size_key}"),
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'style', 'format', '\{size_key}', 'hidden', or 'group')",
        )
    }
  }
  {
    style: combine_style(style_node, format, file~, defs~, context~),
    size,
    hidden,
    outline_level,
  }
}

///|
/// A `group:` outline level: a whole number Excel accepts (0, ungrouped, through
/// `@model.max_outline_level`). Anything else is a diagnostic rather than a
/// backend failure at emit time (ADR-006).
fn expect_outline_level(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Int raise @diag.SchemaError {
  guard node is @yaml.Int(level) else {
    raise schema_error(file~, "\{context} group must be a whole number")
  }
  guard level >= 0 && level <= @model.max_outline_level.to_int64() else {
    raise schema_error(
      file~,
      "\{context} group must be between 0 and \{@model.max_outline_level}",
    )
  }
  level.to_int()
}

///|
/// Parse a column selector into an inclusive 1-based range: `B` -> (2, 2),
/// `D-F` -> (4, 6). A reversed range (`F-D`) is a diagnostic.
fn parse_column_selector(
  selector : String,
  file~ : String,
) -> (Int, Int) raise @diag.SchemaError {
  parse_selector(selector, file~, parse=@units.parse_column, noun="column")
}

///|
/// Parse a row selector into an inclusive 1-based range: `1` -> (1, 1),
/// `2-4` -> (2, 4). A reversed range (`4-2`) is a diagnostic.
fn parse_row_selector(
  selector : String,
  file~ : String,
) -> (Int, Int) raise @diag.SchemaError {
  parse_selector(selector, file~, parse=parse_row_index, noun="row")
}

///|
/// The shape both selectors share: parse the one or two endpoints with `parse`,
/// refuse a reversed range, and name the axis as `noun` in the diagnostics.
fn parse_selector(
  selector : String,
  file~ : String,
  parse~ : (StringView) -> Int?,
  noun~ : String,
) -> (Int, Int) raise @diag.SchemaError {
  let (start, end) = split_range(selector)
  guard parse(start) is Some(first) else {
    raise schema_error(file~, "'\{selector}' is not a valid \{noun}")
  }
  let last = match end {
    Some(end) =>
      match parse(end) {
        Some(last) => last
        None =>
          raise schema_error(file~, "'\{selector}' is not a valid \{noun}")
      }
    None => first
  }
  guard first <= last else {
    raise schema_error(file~, "\{noun} range '\{selector}' is reversed")
  }
  (first, last)
}

///|
/// Split a `start-end` range selector on its single `-`; a bare selector has no
/// end. `A` -> `("A", None)`, `D-F` -> `("D", Some("F"))`.
fn split_range(selector : String) -> (StringView, StringView?) {
  match selector.find("-") {
    Some(index) => (selector[0:index], Some(selector[index + 1:]))
    None => (selector[:], None)
  }
}

///|
/// Parse a run of ASCII digits as a 1-based row index (`>= 1`), or `None`. A row
/// number is a positive integer, so `0` is rejected.
fn parse_row_index(text : StringView) -> Int? {
  match @units.parse_uint(text) {
    Some(value) if value >= 1 => Some(value)
    _ => None
  }
}
