///|
/// Load a parsed YAML document into a workbook model, validating the schema. The
/// spec is a mapping with a `sheets` sequence (and an optional top-level
/// `date1904`); each sheet has a `name` and an optional `cells` mapping of A1
/// reference to a value. A cell value is either a scalar shorthand or an expanded
/// mapping (`value`/`formula`, `type`, `format`) — see `load_cell`.
///
/// ```yaml
/// sheets:
///   - name: Sheet1
///     cells:
///       A1: hello
///       B1: { value: 0.5, format: "0.00%" }
///       C1: { formula: "SUM(B1:B1)" }
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
