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
  let workbook = @model.Workbook::new()
  let mut seen_sheets = false
  for entry in root {
    let (key, value) = entry
    match key {
      "sheets" => {
        seen_sheets = true
        load_sheets(value, workbook, file~)
      }
      _ =>
        raise schema_error(
          file~,
          "unknown top-level key '\{key}' (expected 'sheets')",
        )
    }
  }
  guard seen_sheets else {
    raise schema_error(file~, "missing required key 'sheets'")
  }
  workbook
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
/// A cell is either a scalar shorthand (`A1: 42`) or an expanded mapping with a
/// required `value` and an optional number `format` (`A1: { value: 0.5, format:
/// "0.00%" }`).
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
  let mut value = None
  let mut format = None
  for entry in entries {
    let (key, node) = entry
    match key {
      "value" => value = Some(scalar_value(node, file~, reference~))
      "format" =>
        format = Some(
          expect_string(node, file~, context="cell '\{reference}' format"),
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in cell '\{reference}' (expected 'value' or 'format')",
        )
    }
  }
  guard value is Some(value) else {
    raise schema_error(
      file~,
      "cell '\{reference}' is missing required key 'value'",
    )
  }
  (value, format)
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
fn schema_error(file~ : String, message : String) -> @diag.SchemaError {
  @diag.SchemaError(@diag.Diagnostic::new("\{file}: \{message}"))
}
