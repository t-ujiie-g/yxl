// Loading `validations:` — what Excel will accept in a range: a drop-down, or a
// value measured against a comparison. Split from `decorations.mbt`, which
// holds the smaller sheet keys and the comparison parser this shares with
// `conditional.mbt`.

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
  let at = anchor_range(
    entries,
    file~,
    subject="a validation",
    noun="validation",
  )
  let context = "validation '\{at.to_a1()}'"
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
