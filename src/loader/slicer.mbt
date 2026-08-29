///|
/// A sheet's `slicers:` — a sequence of panels, each anchored at a cell.
fn load_slicers(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'slicers'") {
    sheet.add_slicer(load_slicer(item, file~))
  }
}

///|
/// One `slicers:` entry: where it sits, which table column it filters, and
/// how the panel looks.
fn load_slicer(
  node : @yaml.Node,
  file~ : String,
) -> @model.Slicer raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a slicer")
  let at = anchor_cell(entries, file~, subject="a slicer", noun="slicer")
  let context = "slicer at '\{at.to_a1()}'"
  let mut table = None
  let mut column = None
  let mut caption = None
  let mut width = None
  let mut height = None
  let mut header = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "table" =>
        table = Some(expect_string(value, file~, context="\{context} 'table'"))
      "column" =>
        column = Some(
          expect_string(value, file~, context="\{context} 'column'"),
        )
      "caption" =>
        caption = Some(
          expect_string(value, file~, context="\{context} 'caption'"),
        )
      "size" => {
        let (w, h) = load_shape_size(value, file~, context~)
        width = Some(w)
        height = Some(h)
      }
      "header" =>
        header = Some(expect_bool(value, file~, context="\{context} 'header'"))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'table', 'column', 'caption', 'size', or 'header')",
        )
    }
  }
  guard table is Some(table) else {
    raise schema_error(file~, "\{context} is missing required key 'table'")
  }
  guard column is Some(column) else {
    raise schema_error(file~, "\{context} is missing required key 'column'")
  }
  { at, table, column, caption, width, height, header, }
}

///|
/// A slicer names a table and one of its columns; both must exist by the time
/// the workbook is whole. Runs beside `check_tables`, which has already made
/// table names unique workbook-wide and header rows complete.
fn check_slicers(
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for sheet in workbook.sheets {
    for slicer in sheet.slicers {
      let context = "slicer at '\{slicer.at.to_a1()}' on sheet '\{sheet.name}'"
      // The table is found by name, case-insensitively, as Excel compares
      // them; a slicer cannot reach a table the spec left unnamed.
      let mut found = None
      for table_sheet in workbook.sheets {
        for table in table_sheet.tables {
          if table.name is Some(name) &&
            name.to_lower() == slicer.table.to_lower() {
            found = Some((table_sheet, table))
          }
        }
      }
      guard found is Some((table_sheet, table)) else {
        raise schema_error(
          file~,
          "\{context} filters table '\{slicer.table}', which no sheet declares — a slicer needs a table with that 'name:'",
        )
      }
      // The column must be one of the table's headers, read from the cells
      // the table stands over (the same rule a pivot field follows).
      let headers = header_names(table_sheet, table.at)
      guard headers.contains(slicer.column) else {
        raise schema_error(
          file~,
          "\{context} filters column '\{slicer.column}', which table '\{slicer.table}' does not have (it has \{headers.join(", ")})",
        )
      }
    }
  }
}
