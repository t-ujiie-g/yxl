///|
/// Every column's header levels, how many rows they take, and the style they
/// wear. A `header_style` with no header to wear it is refused.
fn load_layout_header(
  columns : Array[LayoutColumn],
  style_node : @yaml.Node?,
  file~ : String,
  defs~ : Defs,
  context~ : String,
) -> (Array[Array[HeaderCell?]], Int, @model.Style?) raise @diag.SchemaError {
  let headers = columns.map(column => {
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
  let depth = headers.fold(init=0, (deepest, levels) => {
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
  (headers, depth, style)
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
/// Lay out every column's header levels over `depth` rows from `at`, merging
/// as `docs/spec.md` §25 says. Blanks inside a merge wear the header style too,
/// so a fill or a border runs unbroken.
fn write_headers(
  sheet : @model.Sheet,
  headers : Array[Array[HeaderCell?]],
  at~ : @units.CellRef,
  depth~ : Int,
  header_style~ : @model.Style?,
) -> Unit {
  fn place(col : Int, row : Int) -> @units.CellRef {
    @units.CellRef(col=at.col + col, row=at.row + row)
  }

  fn blank(col : Int, row : Int, style : @model.Style?) -> Unit {
    if style is Some(style) {
      sheet.set(place(col, row), Blank, style~)
    }
  }

  // A level stretches when it is its column's last and rows remain below it.
  fn stretches(col : Int, row : Int) -> Bool {
    row == headers[col].length() - 1 && row < depth - 1
  }

  fn same_parents(left : Int, right : Int, row : Int) -> Bool {
    headers[right].length() > row &&
    (0).until(row).all(level => headers[left][level] == headers[right][level])
  }

  for row in 0..<depth {
    let mut col = 0
    while col < headers.length() {
      let levels = headers[col]
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
        sheet.set(place(col, row), cell.value, style?)
        for covered in (row + 1)..<depth {
          blank(col, covered, style)
        }
        sheet.merge(place(col, row), place(col, depth - 1))
        col += 1
        continue
      }
      let mut last = col
      while last + 1 < headers.length() &&
            same_parents(col, last + 1, row) &&
            headers[last + 1][row] == Some(cell) &&
            !stretches(last + 1, row) {
        last += 1
      }
      sheet.set(place(col, row), cell.value, style?)
      for covered in (col + 1)..<=last {
        blank(covered, row, style)
      }
      if last > col {
        sheet.merge(place(col, row), place(last, row))
      }
      col = last + 1
    }
  }
}
