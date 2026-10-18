///|
/// A sheet's `layouts:`, expanded into what the hand-written keys would hold
/// (ADR-023, `docs/spec.md` §25). Named layouts are recorded in `defs` only
/// when `settle`, the pass ahead of the sheets (ADR-026).
fn load_layouts(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
  resolve~ : IncludeResolver,
  settle~ : Bool = false,
) -> Unit raise {
  let names : Map[String, String] = Map([])
  let banded : Map[Int32, String] = Map([])
  for item in expect_seq(node, file~, context="'layouts'") {
    load_layout(item, sheet, file~, defs~, resolve~, names~, banded~, settle~)
  }
}

///|
/// Excel's grid: rows run to 1048576, columns to XFD.
let max_sheet_row : Int32 = 1048576

///|
let max_sheet_column : Int32 = 16384

///|
fn load_layout(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
  resolve~ : IncludeResolver,
  names~ : Map[String, String],
  banded~ : Map[Int32, String],
  settle~ : Bool,
) -> Unit raise {
  let entries = expect_map(node, file~, context="a layout")
  let at = anchor_cell(
    entries,
    file~,
    subject="a layout",
    noun="layout",
    defs~,
    sheet=sheet.name,
  )
  let context = "layout '\{at.to_a1()}'"
  let mut rows = None
  let mut header_style_node = None
  let mut title_node = None
  let mut header_merge_node = None
  let mut body_style_node = None
  let mut columns_node = None
  let mut source = None
  let mut footer_node = None
  let mut name = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "rows" => rows = Some(expect_body_rows(value, file~, context~))
      "header_style" => header_style_node = Some(value)
      "title" => title_node = Some(value)
      "header_merge" => header_merge_node = Some(value)
      "body_style" => body_style_node = Some(value)
      "columns" => columns_node = Some(value)
      "footer" => footer_node = Some(value)
      "name" =>
        name = Some(
          check_layout_name(
            expect_string(value, file~, context="\{context} 'name'"),
            defs~,
            file~,
            context~,
            settle~,
          ),
        )
      "values" | "csv" | "json" => {
        guard source is None else {
          raise schema_error(
            file~,
            "\{context} sets more than one source of rows ('values', 'csv', or 'json')",
          )
        }
        source = Some((key, value))
      }
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'name', 'title', 'rows', 'header_style', 'header_merge', 'body_style', 'columns', 'values', 'csv', 'json', or 'footer')",
        )
    }
  }
  guard columns_node is Some(columns_node) else {
    raise schema_error(file~, "\{context} is missing required key 'columns'")
  }
  let items = expect_seq(columns_node, file~, context="\{context} 'columns'")
  guard !items.is_empty() else {
    raise schema_error(file~, "\{context} has no columns")
  }
  let columns = expand_layout_columns(
    items,
    at_col=at.col,
    file~,
    defs~,
    context~,
  )
  guard at.col + columns.length() - 1 <= max_sheet_column else {
    raise schema_error(
      file~,
      "\{context} has \{columns.length()} columns, which run past Excel's last column (XFD)",
    )
  }
  let inputs = columns.filter(column => column.formula is None)
  let data = load_body_data(source, columns, inputs, file~, resolve~, context~)
  let rows = body_rows(
    rows,
    data,
    has_source=source is Some(_),
    file~,
    context~,
  )
  let col_of = register_names(columns, names~, sheet~, file~, context~)
  let header = load_layout_header(
    columns,
    header_style_node,
    header_merge_node,
    has_title=title_node is Some(_),
    file~,
    defs~,
    context~,
  )
  let merges_before = sheet.merges.length()
  let header_first = if title_node is Some(_) { at.row + 1 } else { at.row }
  let body_first = header_first + header.depth
  let body_last = body_first + rows - 1
  guard body_last <= max_sheet_row else {
    raise schema_error(
      file~,
      "\{context} body ends at row \{body_last}, past Excel's last row (\{max_sheet_row})",
    )
  }
  let layout_body = combine_style(
    body_style_node,
    None,
    file~,
    defs~,
    context="\{context} body_style",
  )
  let body_style_of : Map[String, @model.Style?] = Map([])
  for column in columns {
    body_style_of[column.name] = @model.Style::layer(
      layout_body,
      combine_style(
        column.body_style,
        None,
        file~,
        defs~,
        context="\{context} column '\{column.name}' body_style",
      ),
    )
  }
  if title_node is Some(node) {
    write_title(
      sheet,
      node,
      at~,
      last_col=at.col + columns.length() - 1,
      merge=header.merge,
      file~,
      defs~,
      context~,
    )
  }
  write_headers(sheet, header, at=@units.CellRef(col=at.col, row=header_first))
  let body_inputs = []
  for column in inputs {
    let body_style = body_style_of[column.name]
    let band = load_axis_spec(
      column.band,
      file~,
      defs~,
      size_key="width",
      context="\{context} column '\{column.name}'",
    )
    let formatted = [band.style, body_style].any(style => {
      style is Some({ number_format: Some(_), .. })
    })
    body_inputs.push({
      col: column.col,
      style: body_style,
      type_: if formatted {
        None
      } else {
        column.type_
      },
    })
  }
  write_body_rows(sheet, data, body_inputs, body_first~, rows~)
  merge_equal_runs(sheet, data, inputs, body_first~, file~, context~)
  for column in columns {
    write_layout_column(
      column,
      sheet,
      col_of,
      body_style=body_style_of[column.name],
      body_first~,
      body_last~,
      banded~,
      file~,
      defs~,
      context~,
    )
  }
  let placed = columns.map(column => (column.name, column.col))
  let input_of = Map::from_array(
    inputs.mapi((index, column) => (column.name, index)),
  )
  let mut last_row = body_last
  if footer_node is Some(footer_node) {
    let scope : FooterScope = {
      sheet,
      columns: placed,
      col_of,
      input_of,
      data,
      body_first,
      body_last,
      context,
      file,
      defs,
    }
    let entries = load_footer_entries(
      footer_node,
      scope,
      groups=[],
      has_data=source is Some(_),
    )
    last_row = write_footer(
        entries,
        scope,
        keys=[],
        members=(0).until(data.length()).collect(),
        row=body_last + 1,
      ) -
      1
  }
  if settle && name is Some(name) {
    defs.layouts[name] = {
      sheet: sheet.name,
      columns: placed,
      input_of,
      data,
      first_row: at.row,
      header_first,
      merges: sheet.merges[merges_before:].to_owned(),
      header_row: if header.depth > 0 {
        Some(body_first - 1)
      } else {
        None
      },
      body_first,
      body_last,
      last_row,
    }
  }
}

///|
/// Record each column's name, refusing one another layout on the sheet already
/// uses, and return the layout's own names by column.
fn register_names(
  columns : Array[LayoutColumn],
  names~ : Map[String, String],
  sheet~ : @model.Sheet,
  file~ : String,
  context~ : String,
) -> Map[String, Int32] raise @diag.SchemaError {
  let col_of : Map[String, Int32] = Map([])
  for column in columns {
    if names.get(column.name) is Some(first) {
      raise schema_error(
        file~,
        "\{context} column '\{column.name}' reuses a name \{first} already has on sheet '\{sheet.name}'",
      )
    }
    names[column.name] = context
    col_of[column.name] = column.col
  }
  col_of
}

///|
/// One column's band, filled formula, and conditional formats over the body.
fn write_layout_column(
  column : LayoutColumn,
  sheet : @model.Sheet,
  col_of : Map[String, Int32],
  body_style~ : @model.Style?,
  body_first~ : Int32,
  body_last~ : Int32,
  banded~ : Map[Int32, String],
  file~ : String,
  defs~ : Defs,
  context~ : String,
) -> Unit raise @diag.SchemaError {
  let where_ = "\{context} column '\{column.name}'"
  let body : @model.CellRange = {
    top_left: @units.CellRef(col=column.col, row=body_first),
    bottom_right: @units.CellRef(col=column.col, row=body_last),
  }
  let expand = text => {
    expand_column_refs(
      text,
      col_of,
      row=body_first,
      scope?=column.scope,
      file~,
      context=where_,
    )
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
        "\{where_} lands on a column \{first} already formats; give the column its width and style in one layout, and each body its own look with 'body_style'",
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
      style: body_style,
    })
  }
  guard column.conditional is Some(conditional) else { return }
  for rule in expect_seq(conditional, file~, context="\{where_} 'conditional'") {
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

///|
/// `rows:` — how many body rows the layout spans, at least one.
fn expect_body_rows(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Int32 raise @diag.SchemaError {
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
