///|
/// A named layout as the rest of the spec reaches it (ADR-025): where its
/// columns, header, body and footer landed, and the rows its data held.
priv struct NamedLayout {
  sheet : String
  columns : Array[(String, Int32)]
  input_of : Map[String, Int32]
  data : Rows
  first_row : Int32
  header_first : Int32
  merges : Array[@model.CellRange]
  header_row : Int32?
  body_first : Int32
  body_last : Int32
  last_row : Int32
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
  settle~ : Bool,
) -> String raise @diag.SchemaError {
  guard is_name(name, dots=true) &&
    @units.CellRef::parse_a1(name.to_upper()) is None else {
    raise schema_error(
      file~,
      "\{context} 'name' '\{name}' is not a name Excel accepts: letters, digits, '_' and '.', starting with a letter or '_', and not a cell reference",
    )
  }
  guard settle else { return name }
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
    let table = table_range(placed)
    workbook.add_defined_name(
      name,
      Formula(
        formula="'\{sheet}'!\{table.top_left.to_absolute_a1()}:\{table.bottom_right.to_absolute_a1()}",
        cached=None,
      ),
    )
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
/// A cell of a named layout given by meaning, for an override's, a comment's or
/// a link's `at:` (`what`): a `column` and one of `where`, `row`, `header` or
/// `footer`, or `title` alone. A cell a merge covers is refused.
fn resolve_layout_cell(
  entries : Array[(String, @yaml.Node)],
  defs~ : Defs,
  file~ : String,
  what~ : String,
) -> (String, @units.CellRef) raise @diag.SchemaError {
  let mut layout_name = None
  let mut column = None
  let finders = []
  for entry in entries {
    match entry {
      ("layout", node) =>
        layout_name = Some(
          expect_string(node, file~, context="\{what} 'layout'"),
        )
      ("column", node) =>
        column = Some(expect_string(node, file~, context="\{what} 'column'"))
      ("where" | "row" | "header" | "footer" | "title", _) =>
        finders.push(entry)
      (key, _) =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{what} (expected 'layout', 'column', 'where', 'row', 'header', 'footer', or 'title')",
        )
    }
  }
  guard layout_name is Some(layout_name) else {
    raise schema_error(file~, "\{what} given by layout needs 'layout'")
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
      "\{what} names layout '\{layout_name}', which no layout is called (\{hint})",
    )
  }
  let context = "\{what} on layout '\{layout_name}'"
  guard finders is [(finder, node)] else {
    raise schema_error(
      file~,
      "\{context} needs exactly one of 'where', 'row', 'header', 'footer', or 'title' to find its cell",
    )
  }
  let at = if finder == "title" {
    guard node is @yaml.Bool(true) else {
      raise schema_error(file~, "\{context} 'title' must be true")
    }
    guard column is None else {
      raise schema_error(
        file~,
        "\{context} names a 'column' and the 'title', which spans them all",
      )
    }
    guard layout.header_first > layout.first_row else {
      raise schema_error(
        file~,
        "\{context} names the title of a layout with none",
      )
    }
    @units.CellRef(col=layout.columns[0].1, row=layout.first_row)
  } else {
    guard column is Some(column) else {
      raise schema_error(
        file~,
        "\{context} needs a 'column' to go with its '\{finder}'",
      )
    }
    guard layout.columns.search_by(entry => entry.0 == column) is Some(index) else {
      raise schema_error(
        file~,
        "\{context} names column '\{column}', which the layout does not have",
      )
    }
    let row = match finder {
      "where" =>
        layout.body_first +
        match_where(
          expect_map(node, file~, context="\{context} 'where'"),
          layout,
          file~,
          context~,
        )
      "row" =>
        layout.body_first +
        counted_row(
          node,
          layout.body_last - layout.body_first + 1,
          part="body",
          finder~,
          file~,
          context~,
        ) -
        1
      "header" =>
        layout.header_first +
        counted_row(
          node,
          layout.body_first - layout.header_first,
          part="header",
          finder~,
          file~,
          context~,
        ) -
        1
      _ => {
        let rows = layout.last_row - layout.body_last
        let number = if node is @yaml.Str("last") {
          rows
        } else {
          counted_row(node, rows, part="footer", finder~, file~, context~)
        }
        guard rows > 0 else {
          raise schema_error(
            file~,
            "\{context} names the footer of a layout with none",
          )
        }
        layout.body_last + number
      }
    }
    @units.CellRef(col=layout.columns[index].1, row~)
  }
  for merged in layout.merges {
    guard !within(at, merged) || at == merged.top_left else {
      raise schema_error(
        file~,
        "\{context} lands inside the merged cells '\{merged.to_a1()}'; name their first cell",
      )
    }
  }
  (layout.sheet, at)
}

///|
/// A row band's `at:` as a part of a named layout on `sheet`, `{ layout, part }`:
/// its title, header, body or footer rows, and the band's name in diagnostics.
fn layout_rows(
  entries : Array[(String, @yaml.Node)],
  defs~ : Defs,
  sheet~ : String,
  file~ : String,
) -> (Int32, Int32, String) raise @diag.SchemaError {
  let mut name = None
  let mut part = None
  for entry in entries {
    match entry {
      ("layout", node) =>
        name = Some(expect_string(node, file~, context="row 'at' 'layout'"))
      ("part", node) =>
        part = Some(expect_string(node, file~, context="row 'at' 'part'"))
      (key, _) =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in row 'at' (expected 'layout' or 'part')",
        )
    }
  }
  guard name is Some(name) && part is Some(part) else {
    raise schema_error(
      file~,
      "row 'at' given by layout needs 'layout' and 'part'",
    )
  }
  guard layout_here(name, defs~, sheet~, file~, what="row 'at'") is Some(layout) else {
    let known = defs.layouts.keys().map(name => "'\{name}'").collect()
    raise schema_error(
      file~,
      "row 'at' names layout '\{name}', which is not a named layout (layouts: \{or_list(known)})",
    )
  }
  let (first, last) = match part {
    "title" => (layout.first_row, layout.header_first - 1)
    "header" => (layout.header_first, layout.body_first - 1)
    "body" => (layout.body_first, layout.body_last)
    "footer" => (layout.body_last + 1, layout.last_row)
    other =>
      raise schema_error(
        file~,
        "unknown part '\{other}' of layout '\{name}' (expected 'title', 'header', 'body', or 'footer')",
      )
  }
  guard first <= last else {
    raise schema_error(
      file~,
      "row 'at' names the \{part} of layout '\{name}', which has none",
    )
  }
  (first, last, "the \{part} rows of layout '\{name}'")
}

///|
/// A `row`, `header` or `footer` count: a whole number from 1 to `rows`.
fn counted_row(
  node : @yaml.Node,
  rows : Int32,
  part~ : String,
  finder~ : String,
  file~ : String,
  context~ : String,
) -> Int32 raise @diag.SchemaError {
  guard node is @yaml.Int(number) else {
    raise schema_error(
      file~,
      "\{context} '\{finder}' must be a whole number: the \{part} row, counting from 1",
    )
  }
  guard rows > 0 else {
    raise schema_error(
      file~,
      "\{context} names the \{part} of a layout with none",
    )
  }
  guard number >= 1L && number <= rows.to_int64() else {
    raise schema_error(
      file~,
      "\{context} '\{finder}' is \{number}, but the \{part} has rows 1 to \{rows}",
    )
  }
  number.to_int()
}

///|
/// The one data row whose named input columns hold the given values.
fn match_where(
  conditions : Array[(String, @yaml.Node)],
  layout : NamedLayout,
  file~ : String,
  context~ : String,
) -> Int32 raise @diag.SchemaError {
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

///|
/// A layout as a table: its bottom header row, when it has one, and its body,
/// across every column.
fn table_range(layout : NamedLayout) -> @model.CellRange {
  {
    top_left: @units.CellRef(
      col=layout.columns[0].1,
      row=layout.header_row.unwrap_or(layout.body_first),
    ),
    bottom_right: @units.CellRef(
      col=layout.columns[layout.columns.length() - 1].1,
      row=layout.body_last,
    ),
  }
}

///|
/// The whole of a layout: every header row, the body and the footer.
fn layout_extent(layout : NamedLayout) -> @model.CellRange {
  {
    top_left: @units.CellRef(col=layout.columns[0].1, row=layout.first_row),
    bottom_right: @units.CellRef(
      col=layout.columns[layout.columns.length() - 1].1,
      row=layout.last_row,
    ),
  }
}

///|
/// The layout `name` names, when one does; it must be on `sheet`.
fn layout_here(
  name : String,
  defs~ : Defs,
  sheet~ : String,
  file~ : String,
  what~ : String,
) -> NamedLayout? raise @diag.SchemaError {
  guard defs.layouts.get(name) is Some(layout) else { return None }
  guard layout.sheet == sheet else {
    raise schema_error(
      file~,
      "\{what} '\{name}' names a layout on sheet '\{layout.sheet}', not this one",
    )
  }
  Some(layout)
}

///|
/// A range written as a layout's name: `店舗` is its table, `店舗.cy` a column's
/// body. `None` when `text` names neither, so the caller reads it as a range.
fn layout_range(text : String, defs : Defs) -> @model.SheetRange? {
  for layout in defs.layouts {
    let (name, placed) = layout
    if text == name {
      return Some({ sheet: Some(placed.sheet), range: table_range(placed), })
    }
    guard text.has_prefix("\{name}.") else { continue }
    let column = text[name.length() + 1:].to_owned()
    if placed.columns.search_by(entry => entry.0 == column) is Some(index) {
      let col = placed.columns[index].1
      return Some({
        sheet: Some(placed.sheet),
        range: {
          top_left: @units.CellRef(col~, row=placed.body_first),
          bottom_right: @units.CellRef(col~, row=placed.body_last),
        },
      })
    }
  }
  None
}

///|
/// An anchor written `{ below: layout, gap: n }`: the cell `gap` rows (default
/// 1) under the layout's last row, footer included, in its first column. The
/// layout must be on `sheet` and declared earlier in the spec.
fn below_layout(
  entries : Array[(String, @yaml.Node)],
  defs~ : Defs,
  sheet~ : String,
  file~ : String,
  context~ : String,
) -> @units.CellRef raise @diag.SchemaError {
  let mut below = None
  let mut gap = 1
  for entry in entries {
    match entry {
      ("below", node) =>
        below = Some(expect_string(node, file~, context="\{context} 'below'"))
      ("gap", @yaml.Int(rows)) if rows >= 0L => gap = rows.to_int()
      ("gap", _) =>
        raise schema_error(
          file~,
          "\{context} 'gap' must be a whole number of rows, 0 or more",
        )
      (key, _) =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'below' or 'gap')",
        )
    }
  }
  guard below is Some(name) else {
    raise schema_error(
      file~,
      "\{context} must be a cell, or '{ below: layout }' to follow one",
    )
  }
  guard defs.layouts.get(name) is Some(layout) else {
    raise schema_error(
      file~,
      "\{context} follows layout '\{name}', which no layout declared before it is called",
    )
  }
  guard layout.sheet == sheet else {
    raise schema_error(
      file~,
      "\{context} follows layout '\{name}', which is on sheet '\{layout.sheet}', not this one",
    )
  }
  @units.CellRef(col=layout.columns[0].1, row=layout.last_row + 1 + gap)
}

///|
/// Place every sheet's layouts on scratch sheets ahead of the sheets (ADR-026).
/// A malformed sheet is left to the pass that loads it, which reports it.
fn settle_layouts(
  root : Array[(String, @yaml.Node)],
  defs~ : Defs,
  file~ : String,
  resolve~ : IncludeResolver,
) -> Unit raise {
  guard find_key(root, "sheets") is Some(@yaml.Seq(sheets)) else { return }
  for sheet in sheets {
    guard sheet is @yaml.Map(entries) &&
      find_key(entries, "name") is Some(@yaml.Str(name)) &&
      find_key(entries, "layouts") is Some(layouts) else {
      continue
    }
    load_layouts(
      layouts,
      @model.Sheet(name),
      file~,
      defs~,
      resolve~,
      settle=true,
    )
  }
}
