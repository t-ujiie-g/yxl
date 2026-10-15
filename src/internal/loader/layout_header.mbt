///|
/// A layout's header: each column's levels, how many rows they take, the style
/// they wear, and whether equal neighbours merge.
priv struct LayoutHeader {
  columns : Array[Array[HeaderCell?]]
  depth : Int32
  style : @model.Style?
  merge : Bool
}

///|
/// A `header_style` or `header_merge` with no header to apply to is refused.
fn load_layout_header(
  columns : Array[LayoutColumn],
  style_node : @yaml.Node?,
  merge_node : @yaml.Node?,
  file~ : String,
  defs~ : Defs,
  context~ : String,
) -> LayoutHeader raise @diag.SchemaError {
  let levels_of = columns.map(column => {
    match column.header {
      Some(node) =>
        load_header_levels(
          node,
          file~,
          defs~,
          context="\{context} column '\{column.name}' header",
        )
      None => []
    }
  })
  let depth = levels_of.fold(init=0, (deepest, levels) => {
    if levels.length() > deepest {
      levels.length()
    } else {
      deepest
    }
  })
  let style = combine_style(
    style_node,
    None,
    file~,
    defs~,
    context="\{context} header_style",
  )
  guard !(style is Some(_) && depth == 0) else {
    raise schema_error(
      file~,
      "\{context} has a 'header_style' but no column has a 'header' to wear it",
    )
  }
  let merge = match merge_node {
    Some(node) => {
      guard depth > 0 else {
        raise schema_error(
          file~,
          "\{context} has a 'header_merge' but no column has a 'header' to merge",
        )
      }
      expect_bool(node, file~, context="\{context} 'header_merge'")
    }
    None => true
  }
  { columns: levels_of, depth, style, merge, }
}

///|
/// One header cell as written: its value and its own style. `None` in a level
/// list is a `null`, a cell deliberately left blank.
priv struct HeaderCell {
  value : @model.CellValue
  style : @model.Style?
} derive(Eq)

///|
/// A column's `header:` as its levels, top first: a single cell is one level, a
/// sequence is one per row, and `null` is a blank that merges with nothing.
fn load_header_levels(
  node : @yaml.Node,
  file~ : String,
  defs~ : Defs,
  context~ : String,
) -> Array[HeaderCell?] raise @diag.SchemaError {
  let items = match node {
    @yaml.Seq(items) => items
    single => [single]
  }
  guard !items.is_empty() else {
    raise schema_error(file~, "\{context} is an empty list")
  }
  items.map(item => {
    match item {
      @yaml.Null => None
      @yaml.Seq(_) =>
        raise schema_error(file~, "\{context} levels are cells, not lists")
      cell => {
        let (value, style) = load_cell(cell, file~, reference=context, defs~)
        Some({ value, style, })
      }
    }
  })
}

///|
/// Lay out every column's header levels from `at`, merging as `docs/spec.md`
/// §25 says. Without `merge` the cells are the same, only the ranges go.
fn write_headers(
  sheet : @model.Sheet,
  header : LayoutHeader,
  at~ : @units.CellRef,
) -> Unit {
  let { columns, depth, style: header_style, merge, } = header
  fn place(col : Int32, row : Int32) -> @units.CellRef {
    @units.CellRef(col=at.col + col, row=at.row + row)
  }

  fn blank(col : Int32, row : Int32, style : @model.Style?) -> Unit {
    if style is Some(style) {
      sheet.set(place(col, row), Blank, style~)
    }
  }

  // `cell` over the block from (col, row) to (last_col, last_row), the rest
  // blanks in its style.
  fn span(
    cell : HeaderCell,
    style : @model.Style?,
    col : Int32,
    row : Int32,
    last_col : Int32,
    last_row : Int32,
  ) -> Unit {
    sheet.set(place(col, row), cell.value, style?)
    for covered_row in row..<=last_row {
      for covered_col in col..<=last_col {
        if covered_row != row || covered_col != col {
          blank(covered_col, covered_row, style)
        }
      }
    }
    if merge && (last_col > col || last_row > row) {
      sheet.merge(place(col, row), place(last_col, last_row))
    }
  }

  // A level stretches when it is its column's last and rows remain below it.
  fn stretches(col : Int32, row : Int32) -> Bool {
    row == columns[col].length() - 1 && row < depth - 1
  }

  fn same_parents(left : Int32, right : Int32, row : Int32) -> Bool {
    columns[right].length() > row &&
    (0).until(row).all(level => columns[left][level] == columns[right][level])
  }

  for row in 0..<depth {
    let mut col = 0
    while col < columns.length() {
      let levels = columns[col]
      if row >= levels.length() {
        col += 1
        continue
      }
      guard levels[row] is Some(cell) else {
        let below = if stretches(col, row) { depth - 1 } else { row }
        for blank_row in row..<=below {
          blank(col, blank_row, header_style)
        }
        col += 1
        continue
      }
      let style = @model.Style::layer(header_style, cell.style)
      if stretches(col, row) {
        span(cell, style, col, row, col, depth - 1)
        col += 1
        continue
      }
      let mut last = col
      while last + 1 < columns.length() &&
            same_parents(col, last + 1, row) &&
            columns[last + 1][row] == Some(cell) &&
            !stretches(last + 1, row) {
        last += 1
      }
      span(cell, style, col, row, last, row)
      col = last + 1
    }
  }
}
