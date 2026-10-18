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
    guard !merged.contains(at) || at == merged.top_left else {
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
  let layout = required_layout_here(name, defs~, sheet~, file~, what="row 'at'")
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
