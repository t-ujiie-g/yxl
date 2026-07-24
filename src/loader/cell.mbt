// Cell-value interpretation for the loader: turning a `yaml.Node` cell into a
// `model.CellValue` (+ optional style). Handles the scalar shorthand and the
// expanded `{ value | formula, type, format, style }` form, including explicit
// typing, dates, and error literals. Style parsing lives in `style.mbt`;
// structural loading and the shared `expect_*`/`schema_error` helpers live in
// `loader.mbt`.

///|
/// A cell is either a scalar shorthand (`A1: 42`) or an expanded mapping with an
/// optional `type` (currently `date`), `format`, `style`, and a value source: a
/// `value`, a `formula`, or a `rich` run list — e.g.
/// `A1: { value: 0.5, format: "0.00%" }`, `B1: { value: "2026-07-23", type: date
/// }`, `C1: { formula: "SUM(A1:A2)" }`, or `D1: { rich: ["a ", { text: b, font:
/// { bold: true } }] }`.
fn load_cell(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
  defs~ : Defs,
) -> (@model.CellValue, @model.Style?) raise @diag.SchemaError {
  match node {
    // `A1: { $ref: name }` is the whole-cell shorthand for a named value.
    @yaml.Map(_) if as_ref(node) is Some(name) =>
      (resolve_value_ref(name, file~, reference~, defs~), None)
    @yaml.Map(entries) => load_expanded_cell(entries, file~, reference~, defs~)
    scalar => (scalar_value(scalar, file~, context="cell '\{reference}'"), None)
  }
}

///|
fn load_expanded_cell(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  reference~ : String,
  defs~ : Defs,
) -> (@model.CellValue, @model.Style?) raise @diag.SchemaError {
  let mut value_node = None
  let mut type_ = None
  let mut format = None
  let mut formula = None
  let mut style_node = None
  let mut rich_node = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "value" => value_node = Some(node)
      "type" =>
        type_ = Some(
          expect_string(node, file~, context="cell '\{reference}' type"),
        )
      "format" =>
        format = Some(
          expect_string(node, file~, context="cell '\{reference}' format"),
        )
      "formula" =>
        formula = Some(resolve_formula(node, file~, reference~, defs~))
      "style" => style_node = Some(node)
      "rich" => rich_node = Some(node)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in cell '\{reference}' (expected 'value', 'formula', 'rich', 'type', 'format', or 'style')",
        )
    }
  }
  let (value, number_format) = if rich_node is Some(rich) {
    guard formula is None else {
      raise schema_error(
        file~,
        "cell '\{reference}' cannot combine 'rich' and 'formula'",
      )
    }
    guard value_node is None else {
      raise schema_error(
        file~,
        "cell '\{reference}' cannot combine 'rich' and 'value'",
      )
    }
    guard type_ is None else {
      raise schema_error(
        file~,
        "cell '\{reference}' cannot combine 'rich' and 'type'",
      )
    }
    (load_rich_text(rich, file~, reference~), format)
  } else {
    match formula {
      Some(formula) => {
        guard type_ is None else {
          raise schema_error(
            file~,
            "cell '\{reference}' cannot combine 'formula' and 'type'",
          )
        }
        // A formula's `value` is its optional cached result.
        let cached = match value_node {
          Some(node) =>
            Some(scalar_value(node, file~, context="cell '\{reference}'"))
          None => None
        }
        (@model.Formula(formula=strip_leading_equals(formula), cached~), format)
      }
      None => {
        guard value_node is Some(value_node) else {
          raise schema_error(
            file~,
            "cell '\{reference}' needs a 'value' or a 'formula'",
          )
        }
        if as_ref(value_node) is Some(name) {
          // A `{ $ref: name }` value reuses a named definition; the cell's own
          // `format`/`style` still layer on via `combine_style` below.
          guard type_ is None else {
            raise schema_error(
              file~,
              "cell '\{reference}' cannot combine a '$ref' value with 'type'",
            )
          }
          (resolve_value_ref(name, file~, reference~, defs~), format)
        } else {
          match type_ {
            None =>
              (
                scalar_value(value_node, file~, context="cell '\{reference}'"),
                format,
              )
            Some("text") =>
              (@model.Text(coerce_text(value_node, file~, reference~)), format)
            Some("number") =>
              (
                @model.Number(coerce_number(value_node, file~, reference~)),
                format,
              )
            Some("bool") =>
              (@model.Bool(coerce_bool(value_node, file~, reference~)), format)
            Some("error") =>
              (error_literal(value_node, file~, reference~), format)
            Some("date") =>
              load_date_cell(value_node, format, file~, reference~)
            Some(other) =>
              raise schema_error(
                file~,
                "unknown type '\{other}' for cell '\{reference}' (expected 'text', 'number', 'bool', 'date', or 'error')",
              )
          }
        }
      }
    }
  }
  (
    value,
    combine_style(
      style_node,
      number_format,
      file~,
      defs~,
      context="cell '\{reference}'",
    ),
  )
}

///|
/// Parse a cell's `rich:` sequence into a rich-text value: an ordered list of
/// runs, each a plain string or a `{ text, font }` mapping. Needs at least one
/// run.
fn load_rich_text(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.CellValue raise @diag.SchemaError {
  let items = match node {
    @yaml.Seq(items) => items
    _ =>
      raise schema_error(
        file~,
        "cell '\{reference}' rich text must be a sequence of runs",
      )
  }
  guard !items.is_empty() else {
    raise schema_error(
      file~,
      "cell '\{reference}' rich text needs at least one run",
    )
  }
  let runs = []
  for item in items {
    runs.push(load_rich_run(item, file~, reference~))
  }
  @model.RichText(runs)
}

///|
/// One rich-text run: a plain string (no font) or a `{ text, font }` mapping.
fn load_rich_run(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.RichRun raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => { text, font: None }
    @yaml.Map(entries) => {
      let mut text = None
      let mut font = None
      for entry in entries {
        let (key, node) = entry
        match key {
          "text" =>
            text = Some(
              expect_string(
                node,
                file~,
                context="cell '\{reference}' rich text run 'text'",
              ),
            )
          "font" =>
            font = Some(
              load_font(
                node,
                file~,
                context="cell '\{reference}' rich text run",
              ),
            )
          _ =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in cell '\{reference}' rich text run (expected 'text' or 'font')",
            )
        }
      }
      guard text is Some(text) else {
        raise schema_error(
          file~,
          "cell '\{reference}' rich text run needs a 'text'",
        )
      }
      { text, font }
    }
    _ =>
      raise schema_error(
        file~,
        "cell '\{reference}' rich text run must be text or a mapping",
      )
  }
}

///|
/// Excel stores formulas without the leading `=`; accept a spec that writes one.
fn strip_leading_equals(formula : String) -> String {
  if formula.has_prefix("=") {
    formula[1:].to_owned()
  } else {
    formula
  }
}

///|
/// A `type: date` cell: parse the string value as a date/time and, unless the
/// spec gives a `format`, default to a date or date-time display format.
fn load_date_cell(
  value_node : @yaml.Node,
  format : String?,
  file~ : String,
  reference~ : String,
) -> (@model.CellValue, String?) raise @diag.SchemaError {
  let text = expect_string(
    value_node,
    file~,
    context="date value for '\{reference}'",
  )
  guard @units.DateTime::parse(text) is Some(datetime) else {
    raise schema_error(
      file~,
      "cell '\{reference}' is not a valid date: '\{text}'",
    )
  }
  let format = match format {
    Some(format) => format
    None =>
      if datetime.has_time() {
        "yyyy-mm-dd hh:mm:ss"
      } else {
        "yyyy-mm-dd"
      }
  }
  (@model.Date(datetime), Some(format))
}

///|
/// The Excel error literals a `type: error` cell may hold.
let excel_errors : Array[String] = [
  "#DIV/0!", "#N/A", "#NAME?", "#NULL!", "#NUM!", "#REF!", "#VALUE!", "#SPILL!",
  "#CALC!", "#GETTING_DATA",
]

///|
/// `type: error`: the value must be one of the known Excel error literals.
fn error_literal(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> @model.CellValue raise @diag.SchemaError {
  let text = expect_string(
    node,
    file~,
    context="error value for '\{reference}'",
  )
  guard excel_errors.contains(text) else {
    raise schema_error(
      file~,
      "cell '\{reference}' is not a valid Excel error literal: '\{text}'",
    )
  }
  @model.Error(text)
}

///|
/// `type: text`: render any scalar as its text form.
fn coerce_text(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> String raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => text
    @yaml.Int(number) => number.to_string()
    @yaml.Float(number) => number.to_string()
    @yaml.Bool(flag) => if flag { "true" } else { "false" }
    @yaml.Null | @yaml.Seq(_) | @yaml.Map(_) =>
      raise schema_error(file~, "cell '\{reference}' value cannot be text")
  }
}

///|
/// `type: number`: accept a number, or a string that parses as one.
fn coerce_number(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> Double raise @diag.SchemaError {
  match node {
    @yaml.Int(number) => number.to_double()
    @yaml.Float(number) => number
    @yaml.Str(text) =>
      @string.parse_double(text) catch {
        _ =>
          raise schema_error(
            file~,
            "cell '\{reference}' value is not a number: '\{text}'",
          )
      }
    _ => raise schema_error(file~, "cell '\{reference}' value is not a number")
  }
}

///|
/// `type: bool`: accept a boolean, or the strings `true`/`false`.
fn coerce_bool(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> Bool raise @diag.SchemaError {
  match node {
    @yaml.Bool(flag) => flag
    @yaml.Str("true") => true
    @yaml.Str("false") => false
    _ =>
      raise schema_error(
        file~,
        "cell '\{reference}' value is not a boolean (true or false)",
      )
  }
}

///|
/// Interpret a scalar node as a cell value. A non-scalar here (a nested sequence
/// or mapping in a `value:`) is an error.
fn scalar_value(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> @model.CellValue raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => @model.Text(text)
    @yaml.Int(number) => @model.Number(number.to_double())
    @yaml.Float(number) => @model.Number(number)
    @yaml.Bool(flag) => @model.Bool(flag)
    @yaml.Null | @yaml.Seq(_) | @yaml.Map(_) =>
      raise schema_error(
        file~,
        "\{context} must be text, a number, or a boolean",
      )
  }
}
