///|
/// A sheet's `tables:` — a sequence of tables, each over a range.
fn load_tables(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'tables'") {
    sheet.add_table(load_table(item, file~))
  }
}

///|
/// One `tables:` entry: the range, an optional name and style, and Excel's four
/// appearance toggles.
fn load_table(
  node : @yaml.Node,
  file~ : String,
) -> @model.Table raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a table")
  let at = anchor_range(entries, file~, subject="a table", noun="table")
  let context = "table '\{at.to_a1()}'"
  // Excel's own defaults, as its "Format as Table" applies them.
  let mut name = None
  let mut style = None
  let mut banded_rows = true
  let mut banded_columns = false
  let mut first_column = false
  let mut last_column = false
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "name" =>
        name = Some(
          check_table_name(
            expect_string(value, file~, context="\{context} 'name'"),
            file~,
            context~,
          ),
        )
      "style" =>
        style = Some(
          check_numbered_style(
            expect_string(value, file~, context="\{context} 'style'"),
            @model.table_style_families,
            file~,
            what="table style",
            context~,
          ),
        )
      "banded_rows" =>
        banded_rows = expect_bool(value, file~, context="\{context} '\{key}'")
      "banded_columns" =>
        banded_columns = expect_bool(
          value,
          file~,
          context="\{context} '\{key}'",
        )
      "first_column" =>
        first_column = expect_bool(value, file~, context="\{context} '\{key}'")
      "last_column" =>
        last_column = expect_bool(value, file~, context="\{context} '\{key}'")
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'name', 'style', 'banded_rows', 'banded_columns', 'first_column', or 'last_column')",
        )
    }
  }
  // The top row names the columns and the rows below hold the data, so a table
  // needs both. Excel would grow a one-row range by a row instead, quietly
  // covering a cell the spec never mentioned.
  guard at.bottom_right.row > at.top_left.row else {
    raise schema_error(
      file~,
      "\{context} covers one row; a table needs a header row and at least one row of data",
    )
  }
  { at, name, style, banded_rows, banded_columns, first_column, last_column, }
}

///|
/// A table name, checked against Excel's rules for one: it is a defined name, so
/// it starts with a letter or an underscore, carries no spaces, and cannot be
/// mistaken for a cell reference. Excel refuses to open a workbook that breaks
/// them, so the spec is refused first, by name (ADR-006).
fn check_table_name(
  name : String,
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  fn refuse(reason : String) -> @diag.SchemaError {
    schema_error(file~, "table name '\{name}' \{reason} (\{context})")
  }

  guard name.length() > 0 else {
    raise schema_error(file~, "\{context} has an empty 'name'")
  }
  guard name.length() <= @model.max_defined_name_length else {
    raise refuse(
      "is longer than Excel's \{@model.max_defined_name_length} characters",
    )
  }
  for index, ch in name.iter().to_array() {
    let start = index == 0
    let legal = if start {
      is_name_start(ch)
    } else {
      is_name_start(ch) || ch.is_ascii_digit() || ch == '.'
    }
    guard legal else {
      raise refuse(
        if start {
          "must start with a letter or an underscore"
        } else {
          "may hold only letters, digits, '.' and '_' — no spaces"
        },
      )
    }
  }
  guard @units.CellRef::parse_a1(name) is None else {
    raise refuse("is a cell reference, which Excel will not accept as a name")
  }
  name
}

///|
/// Whether `ch` may start a defined name. Excel allows a backslash there too;
/// it is left out because it reads as a mistake far more often than as intent.
fn is_name_start(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || ch == '_'
}

///|
/// A style from one of Excel's numbered built-in families, checked against them
/// — Excel silently falls back to its default for a name it does not know,
/// which would leave a misspelt style looking like a backend bug. Shared by
/// tables and pivot tables, whose styles are named the same way.
fn check_numbered_style(
  style : String,
  families : Array[(String, Int)],
  file~ : String,
  what~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  for family in families {
    let (prefix, count) = family
    for number in 1..<=count {
      if style == "\{prefix}\{number}" {
        return style
      }
    }
  }
  raise unknown_value(
    style,
    file~,
    what~,
    context~,
    // A family is a range rather than a spelling: listing all 60-odd table
    // styles one by one would bury the mistake it is meant to point at.
    expected=families.map(family => {
      let (prefix, count) = family
      "'\{prefix}1'-'\{prefix}\{count}'"
    }),
  )
}

///|
/// Everything about a table that only the finished workbook can answer: that its
/// name is unique, that it does not overlap another table or the sheet's auto
/// filter, and that its header row names every column.
///
/// Excel repairs — or refuses — a workbook that breaks any of these, and a
/// repair is silent about what it dropped, so each is a diagnostic here instead.
fn check_tables(
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  // Table names share one namespace across the workbook, and Excel compares them
  // without case.
  let names : Map[String, String] = Map([])
  for sheet in workbook.sheets {
    for index, table in sheet.tables {
      let context = "table '\{table.at.to_a1()}' on sheet '\{sheet.name}'"
      if table.name is Some(name) {
        let key = name.to_lower()
        if names.get(key) is Some(owner) {
          raise schema_error(
            file~,
            "\{context} is named '\{name}', which \{owner} already uses",
          )
        }
        names[key] = context
      }
      for earlier in sheet.tables[:index] {
        guard !overlaps(table.at, earlier.at) else {
          raise schema_error(
            file~,
            "\{context} overlaps the table at '\{earlier.at.to_a1()}'; Excel allows a cell in one table only",
          )
        }
      }
      if sheet.filter is Some(filter) && overlaps(table.at, filter) {
        raise schema_error(
          file~,
          "\{context} overlaps the sheet's filter at '\{filter.to_a1()}'; a table carries its own filter buttons",
        )
      }
      check_header_row(sheet, table, file~, context~)
    }
  }
}

///|
/// A table's header row must name every column: Excel identifies a column by its
/// header, and the backend would invent `Column1`, `Column2`, … for the cells
/// left empty — writing them into the sheet, over a spec that never asked for
/// them.
///
/// The name must be text. A number reads as data rather than as a column name,
/// and quoting it says which was meant.
fn check_header_row(
  sheet : @model.Sheet,
  table : @model.Table,
  file~ : String,
  context~ : String,
) -> Unit raise @diag.SchemaError {
  let row = table.at.top_left.row
  let headers = header_row(sheet, table.at)
  let seen : Map[String, Int] = Map([])
  for col in table.at.top_left.col..<=table.at.bottom_right.col {
    let reference = @units.CellRef(col~, row~).to_a1()
    guard headers.get(col) is Some(header) else {
      raise schema_error(
        file~,
        "\{context} has no column name at '\{reference}'; a table's top row must name every column, as text",
      )
    }
    let key = header.to_lower()
    if seen.get(key) is Some(_) {
      raise schema_error(
        file~,
        "\{context} names two columns '\{header}' (at '\{reference}'); Excel needs them distinct",
      )
    }
    seen[key] = col
  }
}

///|
/// The column names written across the top row of `range`, keyed by column. A
/// table, a pivot's source, and the table a slicer filters all identify their
/// columns this way, so all three read the row through here.
///
/// Only a non-empty *text* cell names a column: a number there reads as data,
/// and an empty string names nothing. Columns the row leaves out are simply
/// absent from the map — what to say about them is each caller's own rule.
fn header_row(
  sheet : @model.Sheet,
  range : @model.CellRange,
) -> Map[Int, String] {
  let row = range.top_left.row
  let headers : Map[Int, String] = Map([])
  for cell in sheet.cells {
    guard cell.pos.row == row &&
      cell.pos.col >= range.top_left.col &&
      cell.pos.col <= range.bottom_right.col else {
      continue
    }
    if cell.value is Text(text) && text != "" {
      headers[cell.pos.col] = text
    }
  }
  headers
}

///|
/// The same header row as a list, left to right — the order a diagnostic should
/// name the columns in, and the order Excel shows them in. Left implicit by the
/// map, which is unordered.
fn header_names(
  sheet : @model.Sheet,
  range : @model.CellRange,
) -> Array[String] {
  let headers = header_row(sheet, range)
  let names = []
  for col in range.top_left.col..<=range.bottom_right.col {
    if headers.get(col) is Some(name) {
      names.push(name)
    }
  }
  names
}

///|
/// Whether two ranges share a cell.
fn overlaps(left : @model.CellRange, right : @model.CellRange) -> Bool {
  !(left.bottom_right.row < right.top_left.row ||
  left.top_left.row > right.bottom_right.row ||
  left.bottom_right.col < right.top_left.col ||
  left.top_left.col > right.bottom_right.col)
}
