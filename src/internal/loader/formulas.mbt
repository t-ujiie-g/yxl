///|
/// A sheet's `formulas:` — a sequence of filled ranges.
fn load_formulas(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'formulas'") {
    sheet.add_formula(load_formula_range(item, file~, defs~))
  }
}

///|
/// One `formulas:` entry: the region, the formula as it applies at the
/// region's top-left cell, and the look every cell of it wears.
fn load_formula_range(
  node : @yaml.Node,
  file~ : String,
  defs~ : Defs,
) -> @model.FormulaRange raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a formula range")
  let at = anchor_range(
    entries,
    file~,
    subject="a formula range",
    noun="formula",
  )
  let context = "formula range '\{at.to_a1()}'"
  let mut formula = None
  let mut style_node = None
  let mut format = None
  let mut format_cleared = @model.StyleAttrs::none()
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "formula" => formula = Some(load_filled_formula(value, file~, context~))
      "style" => style_node = Some(value)
      "format" =>
        match value {
          @yaml.Null =>
            format_cleared = @model.StyleAttrs::none().adding(NumberFormat)
          _ =>
            format = Some(
              expect_string(value, file~, context="\{context} 'format'"),
            )
        }
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'formula', 'style', or 'format')",
        )
    }
  }
  guard formula is Some(formula) else {
    raise schema_error(file~, "\{context} is missing required key 'formula'")
  }
  check_formula_range_size(at, file~, context~)
  let style = combine_style(
    style_node,
    format,
    file~,
    defs~,
    context~,
    cleared=format_cleared,
  )
  { at, formula, style, }
}

///|
/// Without a ceiling a mistyped 'A1:A99999999' would build cells until the
/// machine gave up, since a cell reference is not bounded to Excel's grid where
/// it is parsed.
fn check_formula_range_size(
  at : @model.CellRange,
  file~ : String,
  context~ : String,
) -> Unit raise @diag.SchemaError {
  let width = at.bottom_right.col - at.top_left.col + 1
  let height = at.bottom_right.row - at.top_left.row + 1
  guard width.to_int64() * height.to_int64() <=
    @model.max_formula_range_cells.to_int64() else {
    raise schema_error(
      file~,
      "\{context} covers \{width} x \{height} cells, more than the \{@model.max_formula_range_cells} a formula range may fill",
    )
  }
}

///|
/// The `formula:` of a filled range, `=` optional. A `$ref` is refused: it
/// compiles to a defined name, giving every row the first row's answer.
fn load_filled_formula(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  if node is @yaml.Map(entries) && find_key(entries, REF_KEY) is Some(_) {
    raise schema_error(
      file~,
      "\{context} 'formula' cannot be a '\{REF_KEY}': a named formula compiles to a defined name, so every cell would hold the same formula rather than one that shifts per row — write the formula here instead",
    )
  }
  let text = strip_leading_equals(
    expect_string(node, file~, context="\{context} 'formula'"),
  )
  guard !text.is_empty() else {
    raise schema_error(file~, "\{context} has an empty 'formula'")
  }
  text
}

///|
/// A filled range may overlap no other range or written cell. Refusing can be
/// relaxed later; a precedence rule could not be tightened.
fn check_formula_ranges(
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for sheet in workbook.sheets {
    for index, range in sheet.formulas {
      let context = "formula range '\{range.at.to_a1()}' on sheet '\{sheet.name}'"
      for earlier in sheet.formulas[:index] {
        guard !overlaps(range.at, earlier.at) else {
          raise schema_error(
            file~,
            "\{context} overlaps the one at '\{earlier.at.to_a1()}'; a cell can hold one formula",
          )
        }
      }
      for cell in sheet.cells {
        guard !within(cell.pos, range.at) else {
          raise schema_error(
            file~,
            "\{context} covers '\{cell.pos.to_a1()}', which the sheet also writes as a cell; split the range around it rather than letting one silently win",
          )
        }
      }
    }
  }
}

///|
/// Whether a cell falls inside a range.
fn within(cell : @units.CellRef, range : @model.CellRange) -> Bool {
  cell.row >= range.top_left.row &&
  cell.row <= range.bottom_right.row &&
  cell.col >= range.top_left.col &&
  cell.col <= range.bottom_right.col
}
