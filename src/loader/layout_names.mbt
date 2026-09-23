///|
/// A named layout as the rest of the spec reaches it (ADR-025): where its
/// columns and body landed, and the rows its data held.
priv struct NamedLayout {
  sheet : String
  columns : Array[(String, Int)]
  input_of : Map[String, Int]
  data : Rows
  body_first : Int
  body_last : Int
}

///|
/// A layout's `name:` is the first part of a defined name, so it follows
/// Excel's rules for one (letters, digits, `_` and `.`, not a cell reference),
/// and no two layouts share it, ignoring case as Excel does.
fn check_layout_name(
  name : String,
  defs~ : Defs,
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  let chars = name.to_array()
  let valid = !chars.is_empty() &&
    (chars[0].is_ascii_alphabetic() || chars[0] == '_' || !chars[0].is_ascii()) &&
    chars
    .iter()
    .all(ch => {
      ch.is_ascii_alphabetic() ||
      ch.is_ascii_digit() ||
      ch == '_' ||
      ch == '.' ||
      !ch.is_ascii()
    }) &&
    @units.CellRef::parse_a1(name.to_upper()) is None
  guard valid else {
    raise schema_error(
      file~,
      "\{context} 'name' '\{name}' is not a name Excel accepts: letters, digits, '_' and '.', starting with a letter or '_', and not a cell reference",
    )
  }
  for taken in defs.layouts.keys() {
    guard taken.to_lower() != name.to_lower() else {
      raise schema_error(
        file~,
        "\{context} 'name' '\{name}' is already the name of another layout",
      )
    }
  }
  name
}

///|
/// Every column of a named layout as a workbook defined name, `layout.column`,
/// referring to the column's body — the form a formula anywhere reaches it by.
fn add_layout_names(workbook : @model.Workbook, defs : Defs) -> Unit {
  for layout in defs.layouts {
    let (name, placed) = layout
    let sheet = placed.sheet.replace_all(old="'", new="''")
    for column in placed.columns {
      let (column_name, col) = column
      let top = @units.CellRef(col~, row=placed.body_first).to_absolute_a1()
      let bottom = @units.CellRef(col~, row=placed.body_last).to_absolute_a1()
      workbook.add_defined_name(
        "\{name}.\{column_name}",
        Formula(formula="'\{sheet}'!\{top}:\{bottom}", cached=None),
      )
    }
  }
}

///|
/// An override's `at:` given by meaning: `{ layout, column, where | row }`. `where`
/// matches the data's values in the named columns and must find exactly one row.
fn resolve_layout_cell(
  entries : Array[(String, @yaml.Node)],
  defs~ : Defs,
  file~ : String,
) -> (String, @units.CellRef) raise @diag.SchemaError {
  let mut layout_name = None
  let mut column = None
  let mut where_ = None
  let mut row = None
  for entry in entries {
    match entry {
      ("layout", node) =>
        layout_name = Some(
          expect_string(node, file~, context="override 'at' 'layout'"),
        )
      ("column", node) =>
        column = Some(
          expect_string(node, file~, context="override 'at' 'column'"),
        )
      ("where", node) =>
        where_ = Some(expect_map(node, file~, context="override 'at' 'where'"))
      ("row", @yaml.Int(number)) => row = Some(number.to_int())
      ("row", _) =>
        raise schema_error(
          file~,
          "override 'at' 'row' must be a whole number: the body row, counting from 1",
        )
      (key, _) =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in override 'at' (expected 'layout', 'column', 'where', or 'row')",
        )
    }
  }
  guard layout_name is Some(layout_name) && column is Some(column) else {
    raise schema_error(
      file~,
      "override 'at' given by layout needs both 'layout' and 'column'",
    )
  }
  guard defs.layouts.get(layout_name) is Some(layout) else {
    let known = defs.layouts.keys().map(name => "'\{name}'").collect()
    let hint = if known.is_empty() {
      "no layout has a 'name'"
    } else {
      "named: \{or_list(known)}"
    }
    raise schema_error(
      file~,
      "override 'at' names layout '\{layout_name}', which no layout is called (\{hint})",
    )
  }
  let context = "override 'at' on layout '\{layout_name}'"
  guard layout.columns.search_by(entry => entry.0 == column) is Some(index) else {
    raise schema_error(
      file~,
      "\{context} names column '\{column}', which the layout does not have",
    )
  }
  let col = layout.columns[index].1
  let body_row = match (where_, row) {
    (Some(conditions), None) => match_where(conditions, layout, file~, context~)
    (None, Some(number)) => {
      let rows = layout.body_last - layout.body_first + 1
      guard number >= 1 && number <= rows else {
        raise schema_error(
          file~,
          "\{context} 'row' is \{number}, but the body has rows 1 to \{rows}",
        )
      }
      number - 1
    }
    _ =>
      raise schema_error(
        file~,
        "\{context} needs exactly one of 'where' or 'row' to find its row",
      )
  }
  (layout.sheet, @units.CellRef(col~, row=layout.body_first + body_row))
}

///|
/// The one data row whose named input columns hold the given values.
fn match_where(
  conditions : Array[(String, @yaml.Node)],
  layout : NamedLayout,
  file~ : String,
  context~ : String,
) -> Int raise @diag.SchemaError {
  guard !conditions.is_empty() else {
    raise schema_error(file~, "\{context} 'where' names no column")
  }
  let wanted = conditions.map(condition => {
    let (name, node) = condition
    guard layout.input_of.get(name) is Some(field) else {
      raise schema_error(
        file~,
        "\{context} 'where' names '\{name}', which is not a column the layout's data fills",
      )
    }
    (field, scalar_value(node, file~, context="\{context} 'where' '\{name}'"))
  })
  let found = []
  for index, row in layout.data {
    if wanted
      .iter()
      .all(pair => row.get(pair.0).unwrap_or(None) == Some(pair.1)) {
      found.push(index)
    }
  }
  guard found is [only] else {
    raise schema_error(
      file~,
      "\{context} 'where' matches \{found.length()} rows of the data; it must find exactly one",
    )
  }
  only
}

///|
/// Defined names and table names share one namespace, compared without case,
/// and Excel repairs a workbook that repeats one.
fn check_defined_names(
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  let seen : Map[String, String] = Map([])
  let claim = (name : String, what : String) => {
    if seen.get(name.to_lower()) is Some(first) {
      raise schema_error(
        file~,
        "\{what} '\{name}' is also \{first}; Excel keeps one namespace for names and tables, ignoring case",
      )
    }
    seen[name.to_lower()] = "\{what} '\{name}'"
  }
  for defined in workbook.defined_names {
    claim(defined.name, "the defined name")
  }
  for sheet in workbook.sheets {
    for table in sheet.tables {
      if table.name is Some(name) {
        claim(name, "the table")
      }
    }
  }
}
