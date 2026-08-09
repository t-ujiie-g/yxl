///|
/// A diagnostic naming the source file, the pipeline's one way to report a bad
/// spec.
fn schema_error(file~ : String, message : String) -> @diag.SchemaError {
  @diag.SchemaError(@diag.Diagnostic::new("\{file}: \{message}"))
}

///|
/// The spellings a diagnostic offers, in the house form: `'a'`, `'a' or 'b'`,
/// `'a', 'b', or 'c'`. Every "you wrote something that is not one of these"
/// message renders its list through here, so an author meets one shape of
/// suggestion whatever they misspelt.
fn or_list(items : Array[String]) -> String {
  match items {
    [] => ""
    [only] => only
    [first, last] => "\{first} or \{last}"
    [.. rest, last] => "\{rest.join(", ")}, or \{last}"
  }
}

///|
/// A value from a spelling table, or a diagnostic listing every spelling the
/// table holds. `what` names the kind being spelled ("horizontal alignment"),
/// `context` its owner — the same pair every unknown-key diagnostic uses, so a
/// misspelt *value* reads like a misspelt *key*.
fn[T] named(
  table : Array[(String, T)],
  written : String,
  file~ : String,
  what~ : String,
  context~ : String,
) -> T raise @diag.SchemaError {
  for entry in table {
    let (spelling, value) = entry
    if spelling == written {
      return value
    }
  }
  raise unknown_value(
    written,
    file~,
    what~,
    context~,
    expected=table.map(entry => {
      let (spelling, _) = entry
      "'\{spelling}'"
    }),
  )
}

///|
/// The diagnostic behind `named`, for the tables whose membership test is not a
/// lookup — a bare list of allowed names, or a family of numbered styles.
fn unknown_value(
  written : String,
  file~ : String,
  what~ : String,
  context~ : String,
  expected~ : Array[String],
) -> @diag.SchemaError {
  schema_error(
    file~,
    "unknown \{what} '\{written}' in \{context} (expected \{or_list(expected)})",
  )
}

///|
/// The value of the first `key` entry in a mapping's entries, or `None`.
fn find_key(entries : Array[(String, @yaml.Node)], key : String) -> @yaml.Node? {
  for entry in entries {
    let (candidate, value) = entry
    if candidate == key {
      return Some(value)
    }
  }
  None
}

///|
fn expect_map(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Array[(String, @yaml.Node)] raise @diag.SchemaError {
  match node {
    @yaml.Map(entries) => entries
    _ => raise schema_error(file~, "\{context} must be a mapping")
  }
}

///|
fn expect_string(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => text
    _ => raise schema_error(file~, "\{context} must be text")
  }
}

///|
fn expect_seq(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Array[@yaml.Node] raise @diag.SchemaError {
  match node {
    @yaml.Seq(items) => items
    _ => raise schema_error(file~, "\{context} must be a sequence")
  }
}

///|
fn expect_bool(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Bool raise @diag.SchemaError {
  match node {
    @yaml.Bool(flag) => flag
    _ => raise schema_error(file~, "\{context} must be true or false")
  }
}

///|
/// A number scalar (integer or float) as a `Double`.
fn expect_number(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Double raise @diag.SchemaError {
  match node {
    @yaml.Int(number) => number.to_double()
    @yaml.Float(number) => number
    _ => raise schema_error(file~, "\{context} must be a number")
  }
}

///|
/// A hex-color scalar, validated into a `@units.Color`. `what` names the
/// attribute for the diagnostic (e.g. `"font 'color'"`).
fn expect_color(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
  context~ : String,
) -> @units.Color raise @diag.SchemaError {
  let text = expect_string(node, file~, context="\{context} \{what}")
  guard @units.Color::parse(text) is Some(color) else {
    raise schema_error(
      file~,
      "\{context} \{what} is not a valid hex color: '\{text}'",
    )
  }
  color
}

///|
/// An A1-style cell reference, validated. `what` names the construct the
/// reference appeared in, so the diagnostic says *which* one is bad; omit it
/// where the reference is the whole subject (a `cells:` key).
fn expect_cell_ref(
  reference : String,
  file~ : String,
  what? : String,
) -> @units.CellRef raise @diag.SchemaError {
  guard @units.CellRef::parse_a1(reference) is Some(cell) else {
    let within = match what {
      Some(what) => " in \{what}"
      None => ""
    }
    raise schema_error(
      file~,
      "'\{reference}' is not a valid A1 cell reference\{within}",
    )
  }
  cell
}

///|
/// Parse a `TopLeft:BottomRight` range string (e.g. `A1:B2`) into a canonical
/// range — corners may be given in any order. `what` names the range's role in
/// the diagnostics (e.g. `"merge range"`).
fn parse_range(
  text : String,
  file~ : String,
  what~ : String,
) -> @model.CellRange raise @diag.SchemaError {
  guard text.split_once(":") is Some((left, right)) else {
    raise schema_error(file~, "\{what} '\{text}' must be 'TopLeft:BottomRight'")
  }
  // Each corner is parsed on its own rather than through
  // `CellRange::parse`, so a bad one is named in the diagnostic — which corner
  // is wrong is the whole of what a reader needs here (ADR-006).
  let corner = "\{what} '\{text}'"
  let first = expect_cell_ref(left.to_owned(), file~, what=corner)
  let second = expect_cell_ref(right.to_owned(), file~, what=corner)
  let (top_left, bottom_right) = @units.CellRef::rect(first, second)
  { top_left, bottom_right }
}

///|
/// The `at:` that anchors a chart, image, shape, slicer, control, or `data:`
/// table to one cell. `subject` names the construct before its address is known
/// ("a chart", "an image"), `noun` after — which is all that separates the
/// dozen constructs that open this way.
fn anchor_cell(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  subject~ : String,
  noun~ : String,
) -> @units.CellRef raise @diag.SchemaError {
  let text = expect_string(
    required_at(entries, file~, subject~),
    file~,
    context="\{noun} 'at'",
  )
  expect_cell_ref(text, file~, what="\{noun} 'at'")
}

///|
/// The `at:` that anchors a table, pivot, validation, or conditional format to a
/// *region*. The range counterpart of `anchor_cell`; `noun` names the range's
/// role in the diagnostics ("table range").
fn anchor_range(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  subject~ : String,
  noun~ : String,
) -> @model.CellRange raise @diag.SchemaError {
  let text = expect_string(
    required_at(entries, file~, subject~),
    file~,
    context="\{noun} 'at'",
  )
  parse_range(text, file~, what="\{noun} range")
}

///|
/// The `at:` node itself, or the diagnostic for its absence. Split out so the
/// one construct that reads its anchor differently — a band selector, which is a
/// column letter or a row number rather than a cell — words the omission the
/// same way as the rest.
fn required_at(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  subject~ : String,
) -> @yaml.Node raise @diag.SchemaError {
  guard find_key(entries, "at") is Some(node) else {
    raise schema_error(file~, "\{subject} is missing required key 'at'")
  }
  node
}

///|
/// A scalar node, or a diagnostic: text, a number, or a boolean, never a
/// structure. `scalar_value` turns the result into a cell value; parameters keep
/// it as a node.
fn expect_scalar(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @yaml.Node raise @diag.SchemaError {
  match node {
    @yaml.Str(_) | @yaml.Int(_) | @yaml.Float(_) | @yaml.Bool(_) => node
    _ => raise not_scalar(file~, context~)
  }
}

///|
/// A measurement in whole pixels, from `min` (0 for an offset, 1 for a size) up
/// to Excel's drawing ceiling. Shared by charts and images so both refuse an
/// absurd number in the same words.
fn expect_pixels(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
  min~ : Int,
) -> Int raise @diag.SchemaError {
  guard node is @yaml.Int(pixels) else {
    raise schema_error(file~, "\{what} must be a whole number of pixels")
  }
  guard pixels >= min.to_int64() &&
    pixels <= @model.max_drawing_pixels.to_int64() else {
    raise schema_error(
      file~,
      "\{what} must be between \{min} and \{@model.max_drawing_pixels} pixels, not \{pixels}",
    )
  }
  pixels.to_int()
}

///|
/// The diagnostic for a structure where one value belongs. Shared so a cell
/// value and a parameter are refused in the same words.
fn not_scalar(file~ : String, context~ : String) -> @diag.SchemaError {
  schema_error(file~, "\{context} must be text, a number, or a boolean")
}

///|
/// Untyped text as the scalar it looks like. Shared by `--set` values, which
/// arrive from a command line, and CSV fields, which carry no types either — so
/// both read `0.08` as a number and `true` as a boolean, and a spreadsheet built
/// from either holds the same kinds of cell.
fn infer_scalar(text : String) -> @yaml.Node {
  match text {
    "true" => @yaml.Bool(true)
    "false" => @yaml.Bool(false)
    _ => @yaml.Float(@string.parse_double(text)) catch { _ => @yaml.Str(text) }
  }
}
