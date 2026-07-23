///|
/// Load a parsed YAML document into a workbook model, validating the schema. The
/// minimal spec is a mapping with a `sheets` sequence; each sheet has a `name`
/// and an optional `cells` mapping of A1 reference -> scalar:
///
/// ```yaml
/// sheets:
///   - name: Sheet1
///     cells:
///       A1: hello
///       B1: 42
///       C1: true
/// ```
///
/// Unknown keys, wrong types, and bad cell references are `@diag.SchemaError`s
/// (ADR-006). `file` names the source in those diagnostics.
pub fn load(
  document : @yaml.Node,
  file~ : String,
) -> @model.Workbook raise @diag.SchemaError {
  let root = expect_map(document, file~, context="the top level")
  let workbook = @model.Workbook::new(date_system=read_date_system(root, file~))
  let mut seen_sheets = false
  for entry in root {
    let (key, value) = entry
    match key {
      "sheets" => {
        seen_sheets = true
        load_sheets(value, workbook, file~)
      }
      "date1904" => () // consumed by read_date_system
      _ =>
        raise schema_error(
          file~,
          "unknown top-level key '\{key}' (expected 'sheets' or 'date1904')",
        )
    }
  }
  guard seen_sheets else {
    raise schema_error(file~, "missing required key 'sheets'")
  }
  workbook
}

///|
/// The optional top-level `date1904: true` selects the 1904 date system; its
/// absence (or `false`) keeps the 1900 default.
fn read_date_system(
  root : Array[(String, @yaml.Node)],
  file~ : String,
) -> @units.DateSystem raise @diag.SchemaError {
  for entry in root {
    let (key, value) = entry
    if key == "date1904" {
      return if expect_bool(value, file~, context="'date1904'") {
        Date1904
      } else {
        Date1900
      }
    }
  }
  Date1900
}

///|
fn load_sheets(
  node : @yaml.Node,
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  let items = match node {
    @yaml.Seq(items) => items
    _ => raise schema_error(file~, "'sheets' must be a sequence")
  }
  let seen_names = []
  for item in items {
    let name = load_sheet(item, workbook, file~)
    guard !seen_names.contains(name) else {
      raise schema_error(file~, "duplicate sheet name '\{name}'")
    }
    seen_names.push(name)
  }
}

///|
/// Add one sheet to the workbook and return its name (for duplicate checking).
fn load_sheet(
  node : @yaml.Node,
  workbook : @model.Workbook,
  file~ : String,
) -> String raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a sheet")
  let mut name = None
  let mut cells = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "name" => name = Some(expect_string(value, file~, context="sheet 'name'"))
      "cells" => cells = Some(value)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet (expected 'name' or 'cells')",
        )
    }
  }
  guard name is Some(sheet_name) else {
    raise schema_error(file~, "a sheet is missing required key 'name'")
  }
  let sheet = workbook.add_sheet(sheet_name)
  if cells is Some(cells_node) {
    load_cells(cells_node, sheet, file~)
  }
  sheet_name
}

///|
fn load_cells(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="'cells'")
  for entry in entries {
    let (reference, value_node) = entry
    guard @units.CellRef::parse_a1(reference) is Some(cell) else {
      raise schema_error(
        file~,
        "'\{reference}' is not a valid A1 cell reference",
      )
    }
    let (value, format) = load_cell(value_node, file~, reference~)
    sheet.set(cell, value, format?)
  }
}

///|
/// A cell is either a scalar shorthand (`A1: 42`) or an expanded mapping with an
/// optional `type` (currently `date`), `format`, and either a `value` or a
/// `formula` — e.g. `A1: { value: 0.5, format: "0.00%" }`,
/// `B1: { value: "2026-07-23", type: date }`, or `C1: { formula: "SUM(A1:A2)" }`.
fn load_cell(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> (@model.CellValue, String?) raise @diag.SchemaError {
  match node {
    @yaml.Map(entries) => load_expanded_cell(entries, file~, reference~)
    scalar => (scalar_value(scalar, file~, reference~), None)
  }
}

///|
fn load_expanded_cell(
  entries : Array[(String, @yaml.Node)],
  file~ : String,
  reference~ : String,
) -> (@model.CellValue, String?) raise @diag.SchemaError {
  let mut value_node = None
  let mut type_ = None
  let mut format = None
  let mut formula = None
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
        formula = Some(
          expect_string(node, file~, context="cell '\{reference}' formula"),
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in cell '\{reference}' (expected 'value', 'formula', 'type', or 'format')",
        )
    }
  }
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
        Some(node) => Some(scalar_value(node, file~, reference~))
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
      let value = match type_ {
        None => scalar_value(value_node, file~, reference~)
        Some("text") => @model.Text(coerce_text(value_node, file~, reference~))
        Some("number") =>
          @model.Number(coerce_number(value_node, file~, reference~))
        Some("bool") => @model.Bool(coerce_bool(value_node, file~, reference~))
        Some("error") => error_literal(value_node, file~, reference~)
        Some("date") =>
          return load_date_cell(value_node, format, file~, reference~)
        Some(other) =>
          raise schema_error(
            file~,
            "unknown type '\{other}' for cell '\{reference}' (expected 'text', 'number', 'bool', 'date', or 'error')",
          )
      }
      (value, format)
    }
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
  reference~ : String,
) -> @model.CellValue raise @diag.SchemaError {
  match node {
    @yaml.Str(text) => @model.Text(text)
    @yaml.Int(number) => @model.Number(number.to_double())
    @yaml.Float(number) => @model.Number(number)
    @yaml.Bool(flag) => @model.Bool(flag)
    @yaml.Null | @yaml.Seq(_) | @yaml.Map(_) =>
      raise schema_error(
        file~,
        "cell '\{reference}' must be text, a number, or a boolean",
      )
  }
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
fn schema_error(file~ : String, message : String) -> @diag.SchemaError {
  @diag.SchemaError(@diag.Diagnostic::new("\{file}: \{message}"))
}
