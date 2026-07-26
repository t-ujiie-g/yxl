// The sheet keys that decorate cells rather than fill them: `filter:`,
// `validations:`, and `links:`. The fourth, `conditional:`, is large enough for
// its own file and lives in `conditional.mbt`, sharing the comparison parser
// below. Structural loading lives in `loader.mbt`; the shared `expect_*`
// vocabulary lives in `expect.mbt`.

///|
/// A sheet's `filter: <range>` — Excel's auto filter, whose top row is read as
/// the header. One per sheet, so a second `filter:` key simply replaces it (the
/// mapping loader would have rejected the duplicate first).
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
/// A sheet's `validations:` — a sequence of rules, each over a range.
fn load_validations(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'validations'") {
    sheet.add_validation(load_validation(item, file~))
  }
}

///|
/// The rule keys a validation entry may carry, one of which is required. Named
/// here so the diagnostic and the dispatch cannot drift apart.
const VALIDATION_RULES : String = "'list', 'whole', 'decimal', 'text_length', or 'date'"

///|
/// One `validations:` entry: the range it covers, exactly one rule, and the
/// optional blank policy and messages.
fn load_validation(
  node : @yaml.Node,
  file~ : String,
) -> @model.Validation raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a validation")
  guard find_key(entries, "at") is Some(at_node) else {
    raise schema_error(file~, "a validation is missing required key 'at'")
  }
  let at = parse_range(
    expect_string(at_node, file~, context="validation 'at'"),
    file~,
    what="validation range",
  )
  let context = "validation '\{at.top_left.to_a1()}:\{at.bottom_right.to_a1()}'"
  let mut rule : @model.ValidationRule? = None
  // Excel's "Ignore blank", which its own dialog leaves ticked.
  let mut allow_blank = true
  let mut prompt : @model.ValidationPrompt? = None
  let mut error : @model.ValidationError? = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "list" => rule = Some(load_validation_list(value, file~, context~))
      "whole" | "decimal" | "text_length" | "date" => {
        let kind = match key {
          "whole" => @model.Whole
          "decimal" => @model.Decimal
          "text_length" => @model.TextLength
          _ => @model.DateValue
        }
        rule = Some(
          Compare(
            kind~,
            check=load_comparison(
              value,
              file~,
              read_bound=(node, what) => expect_bound(node, file~, kind, what~),
              context~,
            ),
          ),
        )
      }
      "allow_blank" =>
        allow_blank = expect_bool(
          value,
          file~,
          context="\{context} 'allow_blank'",
        )
      "prompt" => prompt = Some(load_prompt(value, file~, context~))
      "error" => error = Some(load_validation_error(value, file~, context~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', \{VALIDATION_RULES}, 'allow_blank', 'prompt', or 'error')",
        )
    }
  }
  guard rule is Some(rule) else {
    raise schema_error(file~, "\{context} needs a rule: \{VALIDATION_RULES}")
  }
  { at, rule, allow_blank, prompt, error }
}

///|
/// A validation's `list:` — either the choices themselves or `{ from: range }`
/// naming the cells holding them.
fn load_validation_list(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ValidationRule raise @diag.SchemaError {
  if node is @yaml.Map(entries) {
    guard entries.length() == 1 && find_key(entries, "from") is Some(from) else {
      raise schema_error(
        file~,
        "\{context} 'list' as a mapping takes exactly one key, 'from'",
      )
    }
    let text = expect_string(from, file~, context="\{context} 'list' from")
    return ListFrom(
      parse_sheet_range(text, file~, what="\{context} 'list' from"),
    )
  }
  let choices = []
  for item in expect_seq(node, file~, context="\{context} 'list'") {
    // Choices are text in the file even when they look like numbers: Excel
    // stores a drop-down as one comma-joined string either way.
    choices.push(
      scalar_text(expect_scalar(item, file~, context="\{context} 'list'")),
    )
  }
  guard !choices.is_empty() else {
    raise schema_error(file~, "\{context} 'list' is empty")
  }
  // Excel stores the choices as one comma-joined formula with a hard length
  // limit; joining here is the only way to know whether it fits.
  let joined_length = choices.fold(init=choices.length() - 1, (total, choice) => {
    total + choice.length()
  })
  guard joined_length <= @model.max_validation_list_length else {
    raise schema_error(
      file~,
      "\{context} 'list' is \{joined_length} characters joined, over Excel's limit of \{@model.max_validation_list_length} — source it from cells with 'list: { from: … }' instead",
    )
  }
  List(choices)
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
/// One endpoint, read as the rule's kind demands: a date rule takes a date
/// string, every other kind takes a number. A whole-number rule additionally
/// refuses a fractional bound, which Excel would compare against but no whole
/// number could ever equal.
fn expect_bound(
  node : @yaml.Node,
  file~ : String,
  kind : @model.ValidationKind,
  what~ : String,
) -> @model.Bound raise @diag.SchemaError {
  if kind is DateValue {
    let text = expect_string(node, file~, context=what)
    guard @units.DateTime::parse(text) is Some(datetime) else {
      raise schema_error(
        file~,
        "\{what} is not a date: '\{text}' (expected YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)",
      )
    }
    return Date(datetime)
  }
  let number = expect_number(node, file~, context=what)
  guard !(kind is Whole && number != number.trunc()) else {
    raise schema_error(
      file~,
      "\{what} must be a whole number: '\{number}' (use 'decimal' for fractions)",
    )
  }
  Number(number)
}

///|
/// A validation's `prompt:` — the pop-up shown when the cell is selected.
fn load_prompt(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ValidationPrompt raise @diag.SchemaError {
  let (title, body) = load_message(node, file~, what="\{context} 'prompt'")
  { title, body }
}

///|
/// A validation's `error:` — what Excel says, and how firmly, about a value the
/// rule rejects.
fn load_validation_error(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.ValidationError raise @diag.SchemaError {
  let what = "\{context} 'error'"
  let entries = expect_map(node, file~, context=what)
  let mut style = @model.Stop
  for entry in entries {
    let (key, value) = entry
    if key == "style" {
      style = match expect_string(value, file~, context="\{what} 'style'") {
        "stop" => @model.Stop
        "warning" => @model.Warning
        "information" => @model.Information
        other =>
          raise schema_error(
            file~,
            "unknown \{what} style '\{other}' (expected 'stop', 'warning', or 'information')",
          )
      }
    }
  }
  let (title, body) = load_message(node, file~, what~, allow_style=true)
  { title, body, style }
}

///|
/// The `{ title, body }` shape both validation messages share. `allow_style`
/// lets the error message's extra key through, so the two callers can share one
/// unknown-key diagnostic.
fn load_message(
  node : @yaml.Node,
  file~ : String,
  what~ : String,
  allow_style? : Bool = false,
) -> (String, String) raise @diag.SchemaError {
  let mut title = ""
  let mut body = ""
  for entry in expect_map(node, file~, context=what) {
    let (key, value) = entry
    match key {
      "title" => title = expect_string(value, file~, context="\{what} 'title'")
      "body" => body = expect_string(value, file~, context="\{what} 'body'")
      "style" if allow_style => () // consumed by the caller
      _ => {
        let expected = if allow_style {
          "'title', 'body', or 'style'"
        } else {
          "'title' or 'body'"
        }
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{what} (expected \{expected})",
        )
      }
    }
  }
  guard !(title == "" && body == "") else {
    raise schema_error(file~, "\{what} needs a 'title' or a 'body'")
  }
  (title, body)
}

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
