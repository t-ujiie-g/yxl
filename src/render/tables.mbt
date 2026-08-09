///|
/// The fewest rows a region needs before a file is better than a `cells:` block.
///
/// Below this the file is pure cost: a reader has to open a second thing to see
/// three values, and a three-line `cells:` block was never the problem `data:`
/// solves. The number is a judgement, not a measurement, which is why the flat
/// form stays one flag away.
pub let min_csv_rows : Int = 8

///|
/// The fewest columns, for the same reason. A single column of numbers is a
/// list, and a list reads fine inline.
pub let min_csv_columns : Int = 2

///|
/// A region of a sheet that will be written as a CSV file rather than as cells:
/// the sheet it belongs to, the cell its top-left field lands on, the `path`
/// the spec will name relative to itself, the file's contents, and the
/// addresses it `covered`, so the `cells:` block can leave them out.
pub(all) struct DataTable {
  sheet : String
  at : @units.CellRef
  path : String
  csv : String
  covered : @set.Set[String]
}

///|
/// The tables worth extracting from a workbook, and the cells they claim.
///
/// One region per sheet at most, and only the obvious one: the largest
/// rectangle of plain literal cells anchored where the sheet's own data starts.
/// Hunting for several regions, or for one that is not anchored at the used
/// range, would be guessing at a layout the file does not describe — and a wrong
/// guess costs a reader more than a missed one.
pub fn data_tables(wb : @model.Workbook) -> Array[DataTable] {
  companion_tables(wb, Names::new())
}

///|
/// The same, against a caller's own name pool rather than a fresh one.
fn companion_tables(wb : @model.Workbook, names : Names) -> Array[DataTable] {
  let tables = []
  for sheet in wb.sheets {
    if literal_region(sheet) is Some(region) {
      let path = names.claim(data_directory, file_stem(sheet.name), "csv")
      tables.push(region_table(sheet, region, path))
    }
  }
  tables
}

///|
/// The rectangle a sheet's literal data occupies, or `None` where it has none
/// worth pulling out.
///
/// "Literal" is strict: a plain text, number, or boolean with no style and no
/// formula. A styled cell belongs in `cells:`, because `data:` carries no
/// formatting (`docs/spec.md` §9) and moving it would silently drop the style.
fn literal_region(sheet : @model.Sheet) -> @model.CellRange? {
  guard bounds(sheet) is Some(bounds) else { return None }
  // The candidate is the whole used rectangle; it survives only if every cell in
  // it is a plain literal, which is the check that makes this safe rather than
  // clever.
  let width = bounds.bottom_right.col - bounds.top_left.col + 1
  let height = bounds.bottom_right.row - bounds.top_left.row + 1
  guard height >= min_csv_rows && width >= min_csv_columns else { return None }
  let filled : @set.Set[String] = Set([])
  for cell in sheet.cells {
    guard is_literal(cell) else { return None }
    filled.add(cell.pos.to_a1())
  }
  // Every cell the sheet has must lie inside the rectangle, and the rectangle
  // must be full: a ragged region would need blank fields the CSV cannot tell
  // from empty text.
  for row in bounds.top_left.row..<=bounds.bottom_right.row {
    for col in bounds.top_left.col..<=bounds.bottom_right.col {
      guard filled.contains(@units.CellRef::new(col~, row~).to_a1()) else {
        return None
      }
    }
  }
  Some(bounds)
}

///|
/// Whether a cell is a plain value the CSV form can carry: no formula, no rich
/// text, no date, no error, and no style of its own.
fn is_literal(cell : @model.Cell) -> Bool {
  guard cell.style is None else { return false }
  cell.value is (Text(_) | Number(_) | Bool(_))
}

///|
/// The rectangle a sheet's cells occupy, or `None` for an empty sheet.
fn bounds(sheet : @model.Sheet) -> @model.CellRange? {
  guard !sheet.cells.is_empty() else { return None }
  let mut left = sheet.cells[0].pos.col
  let mut right = left
  let mut top = sheet.cells[0].pos.row
  let mut bottom = top
  for cell in sheet.cells {
    if cell.pos.col < left {
      left = cell.pos.col
    }
    if cell.pos.col > right {
      right = cell.pos.col
    }
    if cell.pos.row < top {
      top = cell.pos.row
    }
    if cell.pos.row > bottom {
      bottom = cell.pos.row
    }
  }
  Some({
    top_left: @units.CellRef::new(col=left, row=top),
    bottom_right: @units.CellRef::new(col=right, row=bottom),
  })
}

///|
/// Turn a verified region into the table the spec will name.
fn region_table(
  sheet : @model.Sheet,
  region : @model.CellRange,
  path : String,
) -> DataTable {
  let values : Map[String, @model.CellValue] = Map([])
  let covered : @set.Set[String] = Set([])
  for cell in sheet.cells {
    values[cell.pos.to_a1()] = cell.value
    covered.add(cell.pos.to_a1())
  }
  let out = StringBuilder::new()
  for row in region.top_left.row..<=region.bottom_right.row {
    for col in region.top_left.col..<=region.bottom_right.col {
      if col > region.top_left.col {
        out.write_char(',')
      }
      if values.get(@units.CellRef::new(col~, row~).to_a1()) is Some(value) {
        out.write_string(csv_field(value))
      }
    }
    out.write_char('\n')
  }
  {
    sheet: sheet.name,
    at: region.top_left,
    path,
    csv: out.to_string(),
    covered,
  }
}

///|
/// One value as a CSV field.
///
/// Quoting is the loader's rule read backwards (`docs/spec.md` §9): a *bare*
/// field is read as a number or boolean when it looks like one, so text that
/// looks like either has to be quoted to come back as text — which is the same
/// `007` problem the YAML writer solves the same way.
fn csv_field(value : @model.CellValue) -> String {
  match value {
    Number(number) =>
      match number_scalar(number) {
        @yaml.Int(whole) => whole.to_string()
        _ => number.to_string()
      }
    Bool(flag) => if flag { "true" } else { "false" }
    Text(text) =>
      if needs_csv_quoting(text) {
        "\"" + text.replace_all(old="\"", new="\"\"") + "\""
      } else {
        text
      }
    // `literal_region` admits nothing else.
    _ => ""
  }
}

///|
/// Whether a field would come back as something other than the text it is.
fn needs_csv_quoting(text : String) -> Bool {
  guard !text.is_empty() else { return false }
  if text.contains(",") ||
    text.contains("\"") ||
    text.contains("\n") ||
    text.contains("\r") {
    return true
  }
  // The loader reads a bare field as the scalar it looks like, so anything that
  // parses as a number or a boolean must be quoted to stay text.
  if text is ("true" | "false") {
    return true
  }
  guard text.iter().head() is Some(first) else { return false }
  first is ('0'..='9' | '+' | '-' | '.')
}
