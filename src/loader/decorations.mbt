// The smaller sheet keys that decorate cells rather than fill them — `filter:`,
// `links:`, and `comments:` — together with the two parsers the bigger ones
// share: the comparison vocabulary (`validation.mbt`, `conditional.mbt`) and
// sheet-qualified range references.
//
// `validations:` and `conditional:` are each large enough for a file of their
// own. Structural loading lives in `loader.mbt`; the shared `expect_*`
// vocabulary lives in `expect.mbt`.

///|
/// A sheet's `filter: <range>` — Excel's auto filter, whose top row is read as
/// the header. A sheet has at most one, and a spec cannot ask for two: a
/// repeated mapping key is a parse error before this is reached.
fn load_filter(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  let text = expect_string(node, file~, context="sheet 'filter'")
  sheet.set_filter(parse_range(text, file~, what="filter range"))
}

///|
/// A sheet's `links:` — a mapping of cell reference to link. The value is either
/// a URL on its own or a mapping naming the target and a tooltip.
fn load_links(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_map(node, file~, context="'links'") {
    let (reference, value) = entry
    let cell = expect_cell_ref(reference, file~, what="'links'")
    let (target, tip) = load_link(value, file~, reference~)
    sheet.add_link(cell, target, tip?)
  }
}

///|
/// One `links:` entry. A bare string is a URL — the common case, and the one
/// worth writing in one line; an in-workbook target needs the explicit `to:`,
/// since `Summary!A1` and a URL are not distinguishable by shape alone.
fn load_link(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> (@model.LinkTarget, String?) raise @diag.SchemaError {
  let context = "link '\{reference}'"
  if node is @yaml.Str(url) {
    return (Url(url), None)
  }
  let mut target : @model.LinkTarget? = None
  let mut tip : String? = None
  for entry in expect_map(node, file~, context~) {
    let (key, value) = entry
    match key {
      "url" =>
        target = Some(
          Url(expect_string(value, file~, context="\{context} 'url'")),
        )
      "to" =>
        target = Some(
          Location(expect_string(value, file~, context="\{context} 'to'")),
        )
      "tip" =>
        tip = Some(expect_string(value, file~, context="\{context} 'tip'"))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'url', 'to', or 'tip')",
        )
    }
  }
  guard target is Some(target) else {
    raise schema_error(
      file~,
      "\{context} needs 'url' (outside the workbook) or 'to' (inside it)",
    )
  }
  (target, tip)
}

///|
/// A sheet's `comments:` — a mapping of cell reference to note. The value is
/// either the text on its own or a mapping naming the author too.
fn load_comments(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_map(node, file~, context="'comments'") {
    let (reference, value) = entry
    let cell = expect_cell_ref(reference, file~, what="'comments'")
    let context = "comment '\{reference}'"
    if value is @yaml.Str(text) {
      sheet.add_comment(cell, text)
      continue
    }
    let mut text = None
    let mut author = None
    for inner in expect_map(value, file~, context~) {
      let (key, value) = inner
      match key {
        "text" =>
          text = Some(expect_string(value, file~, context="\{context} 'text'"))
        "author" =>
          author = Some(
            expect_string(value, file~, context="\{context} 'author'"),
          )
        _ =>
          raise schema_error(
            file~,
            "unknown key '\{key}' in \{context} (expected 'text' or 'author')",
          )
      }
    }
    guard text is Some(text) else {
      raise schema_error(file~, "\{context} is missing required key 'text'")
    }
    sheet.add_comment(cell, text, author?)
  }
}

///|
/// A comparison: exactly one operator key, whose value is a bound (or a pair of
/// them, for the two-endpoint operators). `read_bound` decides how a bound is
/// read, which is all that differs between a validation — whose declared kind
/// fixes what its bounds may be — and a conditional format, which infers.
///
/// Shared so the two spell their comparisons identically: `at_least` means the
/// same thing wherever it is written.
fn load_comparison(
  node : @yaml.Node,
  file~ : String,
  read_bound~ : (@yaml.Node, String) -> @model.Bound raise @diag.SchemaError,
  context~ : String,
) -> @model.Comparison raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="\{context} rule")
  guard entries.length() == 1 else {
    raise schema_error(
      file~,
      "\{context} rule takes exactly one comparison (\{COMPARISONS})",
    )
  }
  let (key, value) = entries[0]
  let what = "\{context} '\{key}'"
  let pair = () => {
    let items = expect_seq(value, file~, context=what)
    guard items.length() == 2 else {
      raise schema_error(file~, "\{what} takes exactly two bounds, [low, high]")
    }
    (read_bound(items[0], what), read_bound(items[1], what))
  }
  match key {
    "between" => {
      let (low, high) = pair()
      Between(low, high)
    }
    "not_between" => {
      let (low, high) = pair()
      NotBetween(low, high)
    }
    "equals" => Equal(read_bound(value, what))
    "not_equals" => NotEqual(read_bound(value, what))
    "at_least" => AtLeast(read_bound(value, what))
    "at_most" => AtMost(read_bound(value, what))
    "greater_than" => GreaterThan(read_bound(value, what))
    "less_than" => LessThan(read_bound(value, what))
    _ =>
      raise schema_error(
        file~,
        "unknown comparison '\{key}' in \{context} (expected \{COMPARISONS})",
      )
  }
}

///|
const COMPARISONS : String = "'between', 'not_between', 'equals', 'not_equals', 'at_least', 'at_most', 'greater_than', or 'less_than'"

///|
/// Every decoration that names another sheet must name one the workbook
/// declares. This runs once the whole spec is loaded, because a sheet may be
/// referenced before it is declared — a lookup sheet is routinely the last tab.
///
/// A dangling reference is silent in Excel: a drop-down simply comes up empty,
/// and a link goes nowhere. Catching it here is the difference between a
/// diagnostic and a workbook that looks fine until someone clicks (ADR-006).
fn check_cross_sheet_references(
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  fn declared(name : String) -> Bool {
    workbook.sheets.iter().any(sheet => sheet.name == name)
  }

  for sheet in workbook.sheets {
    for validation in sheet.validations {
      if validation.rule is ListFrom({ sheet: Some(source), .. }) &&
        !declared(source) {
        raise schema_error(
          file~,
          "validation on sheet '\{sheet.name}' sources its list from sheet '\{source}', which is not declared",
        )
      }
    }
    for chart in sheet.charts {
      for series in chart.series {
        // A chart plotting a sheet that does not exist opens as an empty frame,
        // saying nothing about which reference went nowhere.
        for source in [Some(series.values), series.categories] {
          guard source is Some({ sheet: Some(named), .. }) else { continue }
          guard declared(named) else {
            raise schema_error(
              file~,
              "chart at '\{chart.at.to_a1()}' on sheet '\{sheet.name}' plots sheet '\{named}', which is not declared",
            )
          }
        }
        guard series.name is Some(FromCell(sheet=Some(named), ..)) else {
          continue
        }
        guard declared(named) else {
          raise schema_error(
            file~,
            "chart at '\{chart.at.to_a1()}' on sheet '\{sheet.name}' names a series from sheet '\{named}', which is not declared",
          )
        }
      }
    }
    for link in sheet.links {
      guard link.target is Location(location) else { continue }
      // Only a sheet-qualified location can be checked; a bare one is a defined
      // name, which the spec may not be the thing that declares.
      guard location_sheet(location) is Some(target) else { continue }
      guard declared(target) else {
        raise schema_error(
          file~,
          "link at '\{link.at.to_a1()}' on sheet '\{sheet.name}' points at sheet '\{target}', which is not declared",
        )
      }
    }
  }
}

///|
/// The sheet a link location names, or `None` when it names none (a defined
/// name). Shares its quoting rules with `split_sheet_prefix`.
fn location_sheet(location : String) -> String? {
  // An unterminated quote is not a sheet reference; leave it to Excel rather
  // than reporting a confusing diagnostic about a link that may be a name.
  let (sheet, _) = split_sheet_prefix(location, file="", what="") catch {
    _ => return None
  }
  sheet
}

///|
/// Parse a possibly sheet-qualified range: `A1:B9`, `Lists!A1:A9`, or
/// `'Q3 data'!A1:A9`. A sheet name is quoted exactly when Excel would quote it,
/// and a `''` inside quotes is one literal quote.
fn parse_sheet_range(
  text : String,
  file~ : String,
  what~ : String,
) -> @model.SheetRange raise @diag.SchemaError {
  let (sheet, rest) = split_sheet_prefix(text, file~, what~)
  { sheet, range: parse_range(rest, file~, what~) }
}

///|
/// Split `Sheet!rest` into its two halves, `None` when no sheet is named.
fn split_sheet_prefix(
  text : String,
  file~ : String,
  what~ : String,
) -> (String?, String) raise @diag.SchemaError {
  let chars = text.iter().to_array()
  guard chars.length() > 0 && chars[0] == '\'' else {
    // Unquoted: Excel requires quotes around any sheet name that could be
    // confused for something else, so the first `!` is the separator.
    return match text.split_once("!") {
      Some((sheet, rest)) => (Some(sheet.to_owned()), rest.to_owned())
      None => (None, text)
    }
  }
  let name = StringBuilder::new()
  let mut index = 1
  while index < chars.length() {
    if chars[index] == '\'' {
      if index + 1 < chars.length() && chars[index + 1] == '\'' {
        name.write_char('\'')
        index += 2
        continue
      }
      break
    }
    name.write_char(chars[index])
    index += 1
  }
  // `index` is at the closing quote, which must be followed by `!range`.
  guard index + 1 < chars.length() &&
    chars[index] == '\'' &&
    chars[index + 1] == '!' else {
    raise schema_error(
      file~,
      "\{what} '\{text}' has an unterminated quoted sheet name (expected \"'Sheet name'!A1:B9\")",
    )
  }
  let rest = StringBuilder::new()
  for taken in (index + 2)..<chars.length() {
    rest.write_char(chars[taken])
  }
  (Some(name.to_string()), rest.to_string())
}
