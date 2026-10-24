///|
/// A layout's header: each column's levels, how many rows they take, the style
/// each row wears (the last one for every row past the list), and whether
/// equal neighbours merge.
priv struct LayoutHeader {
  columns : Array[Array[HeaderCell?]]
  depth : Int32
  styles : Array[@model.Style?]
  merge : Bool
}

///|
/// The style the header's `row` wears.
fn LayoutHeader::style_at(self : LayoutHeader, row : Int32) -> @model.Style? {
  match self.styles {
    [] => None
    styles =>
      styles[if row < styles.length() { row } else { styles.length() - 1 }]
  }
}

///|
/// A `header_style` with no header to apply to is refused, as is a
/// `header_merge` with neither a header nor a title, and a `header_style` list
/// longer than the header is deep.
fn load_layout_header(
  columns : Array[LayoutColumn],
  style_node : @yaml.Node?,
  merge_node : @yaml.Node?,
  has_title~ : Bool,
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
  let style_nodes = match style_node {
    Some(@yaml.Seq(items)) => {
      guard !items.is_empty() else {
        raise schema_error(file~, "\{context} 'header_style' is an empty list")
      }
      items
    }
    Some(node) => [node]
    None => []
  }
  guard style_nodes.is_empty() || depth > 0 else {
    raise schema_error(
      file~,
      "\{context} has a 'header_style' but no column has a 'header' to wear it",
    )
  }
  guard style_nodes.length() <= depth else {
    raise schema_error(
      file~,
      "\{context} 'header_style' lists \{style_nodes.length()} styles, but the header is \{depth} rows deep",
    )
  }
  let styles = style_nodes.map(node => {
    combine_style(
      Some(node),
      None,
      file~,
      defs~,
      context="\{context} header_style",
    )
  })
  let merge = match merge_node {
    Some(node) => {
      guard depth > 0 || has_title else {
        raise schema_error(
          file~,
          "\{context} has a 'header_merge' but no 'title' or column 'header' to merge",
        )
      }
      expect_bool(node, file~, context="\{context} 'header_merge'")
    }
    None => true
  }
  { columns: levels_of, depth, styles, merge, }
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
/// §25 says. Without `merge` the ranges go, and with them the border edges
/// inside each, which a merge would not draw.
fn write_headers(
  sheet : @model.Sheet,
  header : LayoutHeader,
  at~ : @units.CellRef,
) -> Unit {
  let { columns, depth, merge, .. } = header
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
    let style_at = (at_col : Int32, at_row : Int32) => {
      if merge {
        style
      } else {
        inner_edges_dropped(
          style,
          left=at_col > col,
          right=at_col < last_col,
          top=at_row > row,
          bottom=at_row < last_row,
        )
      }
    }
    sheet.set(place(col, row), cell.value, style?=style_at(col, row))
    for covered_row in row..<=last_row {
      for covered_col in col..<=last_col {
        if covered_row != row || covered_col != col {
          blank(covered_col, covered_row, style_at(covered_col, covered_row))
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
          blank(col, blank_row, header.style_at(row))
        }
        col += 1
        continue
      }
      let style = @model.Style::layer(header.style_at(row), cell.style)
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

///|
/// `style` without the border edges flagged, each one cleared so no band shows
/// through. An edge the style does not set is left alone (#122).
fn inner_edges_dropped(
  style : @model.Style?,
  left~ : Bool,
  right~ : Bool,
  top~ : Bool,
  bottom~ : Bool,
) -> @model.Style? {
  guard style is Some(style) && style.borders is Some(borders) else {
    return style
  }
  let mut cleared = @model.StyleAttrs::none()
  let edge = (side : @model.Border?, inner : Bool, attr : @model.StyleAttr) => {
    if inner && side is Some(_) {
      cleared = cleared.adding(attr)
      None
    } else {
      side
    }
  }
  let kept = @model.Borders::{
    left: edge(borders.left, left, BorderLeft),
    right: edge(borders.right, right, BorderRight),
    top: edge(borders.top, top, BorderTop),
    bottom: edge(borders.bottom, bottom, BorderBottom),
  }
  let borders = if kept == @model.Borders::empty() { None } else { Some(kept) }
  Some({ ..style, borders, }.clearing(cleared))
}

///|
/// A layout's `title:`, a cell across its width in the row above the header:
/// merged, or with `merge` off the value in the first cell and the rest blanks
/// in its style, the border edges between them dropped.
fn write_title(
  sheet : @model.Sheet,
  node : @yaml.Node,
  at~ : @units.CellRef,
  last_col~ : Int32,
  merge~ : Bool,
  file~ : String,
  defs~ : Defs,
  context~ : String,
) -> Unit raise @diag.SchemaError {
  let (value, style) = load_cell(
    node,
    file~,
    reference="\{context} title",
    defs~,
  )
  let style_at = (col : Int32) => {
    if merge {
      style
    } else {
      inner_edges_dropped(
        style,
        left=col > at.col,
        right=col < last_col,
        top=false,
        bottom=false,
      )
    }
  }
  sheet.set(at, value, style?=style_at(at.col))
  for col in (at.col + 1)..<=last_col {
    if style_at(col) is Some(style) {
      sheet.set(@units.CellRef(col~, row=at.row), Blank, style~)
    }
  }
  if merge && last_col > at.col {
    sheet.merge(at, @units.CellRef(col=last_col, row=at.row))
  }
}
