///|
/// Read `defs.blocks`: each a named group of layout columns (ADR-023). The
/// columns are read where an instance places them, since their positions and
/// qualified names only exist there.
fn load_block_defs(
  node : @yaml.Node,
  defs : Defs,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for entry in expect_map(node, file~, context="'defs.blocks'") {
    let (name, body) = entry
    let context = "block '\{name}'"
    let mut columns = None
    for key in expect_map(body, file~, context~) {
      match key.0 {
        "columns" =>
          columns = Some(
            expect_seq(key.1, file~, context="\{context} 'columns'"),
          )
        other =>
          raise schema_error(
            file~,
            "unknown key '\{other}' in \{context} (expected 'columns')",
          )
      }
    }
    guard columns is Some(columns) && !columns.is_empty() else {
      raise schema_error(file~, "\{context} needs at least one column")
    }
    for column in columns {
      if column is @yaml.Map(entries) && find_key(entries, "block") is Some(_) {
        raise schema_error(
          file~,
          "\{context} places another block; blocks do not nest",
        )
      }
    }
    defs.blocks[name] = columns
  }
}

///|
/// A layout's `columns:` with every block instance replaced by its columns, left
/// to right from `at_col`. An instance's columns are named `as.name`, resolve
/// `{{name}}` in the instance first, and carry its `header` as their top level.
fn expand_layout_columns(
  items : Array[@yaml.Node],
  at_col~ : Int,
  file~ : String,
  defs~ : Defs,
  context~ : String,
) -> Array[LayoutColumn] raise @diag.SchemaError {
  let columns = []
  let instances = []
  for item in items {
    guard item is @yaml.Map(entries) &&
      find_key(entries, "block") is Some(block_node) else {
      columns.push(
        load_layout_column(item, col=at_col + columns.length(), file~, context~),
      )
      continue
    }
    let block = expect_string(block_node, file~, context="\{context} 'block'")
    guard defs.blocks.get(block) is Some(block_columns) else {
      let known = defs.blocks.keys().map(name => "'\{name}'").collect()
      let hint = if known.is_empty() {
        "no blocks are declared"
      } else {
        "declared: \{or_list(known)}"
      }
      raise schema_error(
        file~,
        "\{context} places block '\{block}', which 'defs.blocks' does not declare (\{hint})",
      )
    }
    let mut name = block
    let mut header = None
    let mut fields = None
    for entry in entries {
      match entry.0 {
        "block" => ()
        "as" => name = expect_string(entry.1, file~, context="\{context} 'as'")
        "header" => header = Some(entry.1)
        "fields" =>
          fields = Some(
            expect_map(entry.1, file~, context="\{context} '\{name}' fields"),
          )
        other =>
          raise schema_error(
            file~,
            "unknown key '\{other}' in \{context} block '\{block}' (expected 'block', 'as', 'header', or 'fields')",
          )
      }
    }
    check_column_name(name, file~, context~)
    guard !instances.contains(name) else {
      raise schema_error(
        file~,
        "\{context} places two blocks as '\{name}'; give one of them another 'as'",
      )
    }
    instances.push(name)
    let first = at_col + columns.length()
    let placed = block_columns.mapi((index, node) => {
      load_layout_column(node, col=first + index, file~, context~)
    })
    let named = placed.map(column => column.name)
    for field in fields.unwrap_or([]) {
      guard placed.search_by(column => column.name == field.0) is Some(index) &&
        placed[index].formula is None else {
        raise schema_error(
          file~,
          "\{context} '\{name}' fields names '\{field.0}', which is not a column of block '\{block}' the data fills (\{or_list(named.map(n => "'\{n}'"))})",
        )
      }
    }
    for column in placed {
      let field = match find_key(fields.unwrap_or([]), column.name) {
        Some(node) =>
          Some(
            expect_string(
              node,
              file~,
              context="\{context} '\{name}' field of '\{column.name}'",
            ),
          )
        None => column.field
      }
      columns.push({
        ..column,
        name: "\{name}.\{column.name}",
        scope: Some(name),
        header: prepend_header(header, column.header),
        field,
      })
    }
  }
  for column in columns {
    if column.scope is None && instances.contains(column.name) {
      raise schema_error(
        file~,
        "\{context} column '\{column.name}' has the name of a block placed in the same layout",
      )
    }
  }
  columns
}

///|
/// An instance's header as the top level above a block column's own levels.
fn prepend_header(top : @yaml.Node?, levels : @yaml.Node?) -> @yaml.Node? {
  let as_levels = (node : @yaml.Node) => {
    match node {
      @yaml.Seq(items) => items
      single => [single]
    }
  }
  match (top, levels) {
    (Some(top), Some(levels)) =>
      Some(Seq([..as_levels(top), ..as_levels(levels)]))
    (None, levels) => levels
    (top, None) => top
  }
}
