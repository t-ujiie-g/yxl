///|
/// A sheet's `layouts:` — regions of named columns, each expanded into the
/// bands, header cells, formula ranges and conditional formats a hand-written
/// spec would hold (ADR-023, `docs/spec.md` §25). Column names are unique across
/// the sheet, and one column carries a band from at most one layout.
fn load_layouts(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  let names : Map[String, String] = Map([])
  let banded : Map[Int, String] = Map([])
  for item in expect_seq(node, file~, context="'layouts'") {
    load_layout(item, sheet, file~, defs~, names~, banded~)
  }
}

///|
/// The keys a layout column reads itself; the rest are its band's (§4).
let layout_column_keys : Array[String] = [
  "name", "header", "formula", "conditional",
]

///|
/// The keys a layout column passes to its column band.
let layout_band_keys : Array[String] = [
  "width", "style", "format", "hidden", "group",
]

///|
/// Excel's grid: rows run to 1048576, columns to XFD.
let max_sheet_row : Int = 1048576

///|
let max_sheet_column : Int = 16384

///|
/// One column of a layout as written, before it is placed.
priv struct LayoutColumn {
  name : String
  col : Int
  header : @yaml.Node?
  formula : @yaml.Node?
  conditional : @yaml.Node?
  band : Array[(String, @yaml.Node)]
}

///|
fn load_layout(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
  names~ : Map[String, String],
  banded~ : Map[Int, String],
) -> Unit raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a layout")
  let at = anchor_cell(entries, file~, subject="a layout", noun="layout")
  let context = "layout '\{at.to_a1()}'"
  let mut rows = None
  let mut header_style_node = None
  let mut columns_node = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "rows" => rows = Some(expect_body_rows(value, file~, context~))
      "header_style" => header_style_node = Some(value)
      "columns" => columns_node = Some(value)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'rows', 'header_style', or 'columns')",
        )
    }
  }
  guard rows is Some(rows) else {
    raise schema_error(file~, "\{context} is missing required key 'rows'")
  }
  guard columns_node is Some(columns_node) else {
    raise schema_error(file~, "\{context} is missing required key 'columns'")
  }
  let items = expect_seq(columns_node, file~, context="\{context} 'columns'")
  guard !items.is_empty() else {
    raise schema_error(file~, "\{context} has no columns")
  }
  guard at.col + items.length() - 1 <= max_sheet_column else {
    raise schema_error(
      file~,
      "\{context} has \{items.length()} columns, which run past Excel's last column (XFD)",
    )
  }
  let columns = items.mapi((index, item) => {
    load_layout_column(item, col=at.col + index, file~, context~)
  })
  let in_layout : Map[String, Int] = Map([])
  for column in columns {
    let where_ = "\{context} column '\{column.name}'"
    if names.get(column.name) is Some(first) {
      raise schema_error(
        file~,
        "\{where_} reuses a name \{first} already has on sheet '\{sheet.name}'",
      )
    }
    names[column.name] = context
    in_layout[column.name] = column.col
  }
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
  let has_header = depth > 0
  let header_style = combine_style(
    header_style_node,
    None,
    file~,
    defs~,
    context="\{context} header_style",
  )
  guard !(header_style is Some(_) && !has_header) else {
    raise schema_error(
      file~,
      "\{context} has a 'header_style' but no column has a 'header' to wear it",
    )
  }
  let body_first = at.row + depth
  let body_last = body_first + rows - 1
  guard body_last <= max_sheet_row else {
    raise schema_error(
      file~,
      "\{context} body ends at row \{body_last}, past Excel's last row (\{max_sheet_row})",
    )
  }
  write_headers(sheet, headers, at~, depth~, header_style~)
  for column in columns {
    let where_ = "\{context} column '\{column.name}'"
    let body : @model.CellRange = {
      top_left: @units.CellRef(col=column.col, row=body_first),
      bottom_right: @units.CellRef(col=column.col, row=body_last),
    }
    let expand = text => {
      expand_column_refs(text, in_layout, row=body_first, file~, context=where_)
    }
    let band = load_axis_spec(
      column.band,
      file~,
      defs~,
      size_key="width",
      context=where_,
    )
    if !band.is_empty() {
      if banded.get(column.col) is Some(first) {
        raise schema_error(
          file~,
          "\{where_} lands on a column \{first} already formats; give the column its width and style in one layout",
        )
      }
      banded[column.col] = where_
      sheet.set_column_band(
        first=column.col,
        last=column.col,
        style?=band.style,
        width?=band.size,
        hidden?=band.hidden,
        outline_level?=band.outline_level,
      )
    }
    if column.formula is Some(formula) {
      let formula = match formula {
        @yaml.Str(text) => @yaml.Str(expand(text))
        other => other
      }
      check_formula_range_size(body, file~, context=where_)
      sheet.add_formula({
        at: body,
        formula: load_filled_formula(formula, file~, context=where_),
      })
    }
    if column.conditional is Some(conditional) {
      for
        rule in expect_seq(
          conditional,
          file~,
          context="\{where_} 'conditional'",
        ) {
        let rule_entries = expect_map(
          rule,
          file~,
          context="a conditional format of \{where_}",
        )
        guard find_key(rule_entries, "at") is None else {
          raise schema_error(
            file~,
            "a conditional format of \{where_} takes no 'at'; it covers the column's body",
          )
        }
        sheet.add_conditional_format(
          load_conditional_rule(
            rule_entries,
            body,
            file~,
            defs~,
            context="conditional of \{where_}",
            expected_before=[],
            formula=expand,
          ),
        )
      }
    }
  }
}

///|
/// `rows:` — how many body rows the layout spans, at least one.
fn expect_body_rows(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Int raise @diag.SchemaError {
  guard node is @yaml.Int(rows) && rows >= 1L else {
    raise schema_error(
      file~,
      "\{context} 'rows' must be a whole number of at least 1",
    )
  }
  guard rows <= max_sheet_row.to_int64() else {
    raise schema_error(
      file~,
      "\{context} 'rows' is \{rows}, more than Excel's \{max_sheet_row}",
    )
  }
  rows.to_int()
}

///|
/// Split one layout column into what the layout reads and what its band reads.
fn load_layout_column(
  node : @yaml.Node,
  col~ : Int,
  file~ : String,
  context~ : String,
) -> LayoutColumn raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a column of \{context}")
  guard find_key(entries, "name") is Some(name_node) else {
    raise schema_error(
      file~,
      "a column of \{context} is missing required key 'name'",
    )
  }
  let name = expect_string(
    name_node,
    file~,
    context="a column of \{context} 'name'",
  )
  check_column_name(name, file~, context~)
  let where_ = "\{context} column '\{name}'"
  let mut header = None
  let mut formula = None
  let mut conditional = None
  let band = []
  for entry in entries {
    let (key, value) = entry
    match key {
      "name" => ()
      "header" => header = Some(value)
      "formula" => formula = Some(value)
      "conditional" => conditional = Some(value)
      _ if layout_band_keys.contains(key) => band.push(entry)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{where_} (expected \{or_list([..layout_column_keys, ..layout_band_keys].map(k => "'\{k}'"))})",
        )
    }
  }
  { name, col, header, formula, conditional, band, }
}

///|
/// A column name is what `{{name}}` can spell: letters, digits and `_`, or any
/// non-ASCII character, and not a leading digit. `.` stays free to qualify a
/// block's columns.
fn check_column_name(
  name : String,
  file~ : String,
  context~ : String,
) -> Unit raise @diag.SchemaError {
  let chars = name.to_array()
  let valid = !chars.is_empty() &&
    !chars[0].is_ascii_digit() &&
    chars
    .iter()
    .all(ch => {
      ch.is_ascii_alphabetic() ||
      ch.is_ascii_digit() ||
      ch == '_' ||
      !ch.is_ascii()
    })
  guard valid else {
    raise schema_error(
      file~,
      "column name '\{name}' in \{context} must be letters, digits and '_', not starting with a digit",
    )
  }
}

///|
/// Replace each `{{name}}` in a formula with that column's cell in `row`.
/// Text inside a `"…"` string literal is left alone (`""` escapes a quote).
fn expand_column_refs(
  text : String,
  columns : Map[String, Int],
  row~ : Int,
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  let chars = text.to_array()
  let out = StringBuilder()
  let mut quoted = false
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '"' {
      quoted = !quoted
    } else if !quoted &&
      ch == '{' &&
      i + 1 < chars.length() &&
      chars[i + 1] == '{' {
      let mut end = i + 2
      while end + 1 < chars.length() &&
            !(chars[end] == '}' && chars[end + 1] == '}') {
        end += 1
      }
      guard end + 1 < chars.length() else {
        raise schema_error(
          file~,
          "\{context} formula has a '{{' with no closing '}}'",
        )
      }
      let name = String::from_array(chars[i + 2:end])
      guard columns.get(name) is Some(col) else {
        let known = columns.keys().map(k => "'\{k}'").collect()
        raise schema_error(
          file~,
          "\{context} formula refers to '{{\{name}}}', which is not a column of this layout (\{or_list(known)})",
        )
      }
      out.write_string(@units.CellRef(col~, row~).to_a1())
      i = end + 2
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
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
/// Lay out every column's header levels over `depth` rows from `at`. A column
/// with fewer levels than `depth` stretches its last one down; adjacent columns
/// whose level holds the same cell under the same parents share one merge.
/// Every cell of a merge, and every blank, wears the header style, so a fill
/// or a border runs unbroken across the block.
fn write_headers(
  sheet : @model.Sheet,
  headers : Array[Array[HeaderCell?]],
  at~ : @units.CellRef,
  depth~ : Int,
  header_style~ : @model.Style?,
) -> Unit {
  fn look(cell : HeaderCell) -> @model.Style? {
    match (cell.style, header_style) {
      (Some(own), Some(base)) => Some(own.over(base))
      (Some(own), None) => Some(own)
      (None, base) => base
    }
  }

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
      let style = look(cell)
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
