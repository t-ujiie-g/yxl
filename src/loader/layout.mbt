///|
/// A sheet's `layouts:`, expanded into what the hand-written keys would hold
/// (ADR-023, `docs/spec.md` §25). `names` and `banded` span the sheet.
fn load_layouts(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
  resolve~ : IncludeResolver,
) -> Unit raise {
  let names : Map[String, String] = Map([])
  let banded : Map[Int, String] = Map([])
  for item in expect_seq(node, file~, context="'layouts'") {
    load_layout(item, sheet, file~, defs~, resolve~, names~, banded~)
  }
}

///|
/// The keys a layout column reads itself; the rest are its band's (§4).
let layout_column_keys : Array[String] = [
  "name", "header", "field", "formula", "conditional",
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
  scope : String?
  field : String?
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
  resolve~ : IncludeResolver,
  names~ : Map[String, String],
  banded~ : Map[Int, String],
) -> Unit raise {
  let entries = expect_map(node, file~, context="a layout")
  let at = anchor_cell(entries, file~, subject="a layout", noun="layout")
  let context = "layout '\{at.to_a1()}'"
  let mut rows = None
  let mut header_style_node = None
  let mut columns_node = None
  let mut source = None
  let mut footer_node = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "rows" => rows = Some(expect_body_rows(value, file~, context~))
      "header_style" => header_style_node = Some(value)
      "columns" => columns_node = Some(value)
      "footer" => footer_node = Some(value)
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
          "unknown key '\{key}' in \{context} (expected 'at', 'rows', 'header_style', 'columns', 'values', 'csv', 'json', or 'footer')",
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
  let (headers, depth, header_style) = load_layout_header(
    columns,
    header_style_node,
    file~,
    defs~,
    context~,
  )
  let body_first = at.row + depth
  let body_last = body_first + rows - 1
  guard body_last <= max_sheet_row else {
    raise schema_error(
      file~,
      "\{context} body ends at row \{body_last}, past Excel's last row (\{max_sheet_row})",
    )
  }
  write_headers(sheet, headers, at~, depth~, header_style~)
  write_body_rows(sheet, data, inputs, body_first~)
  for column in columns {
    write_layout_column(
      column,
      sheet,
      col_of,
      body_first~,
      body_last~,
      banded~,
      file~,
      defs~,
      context~,
    )
  }
  if footer_node is Some(footer_node) {
    let scope : FooterScope = {
      sheet,
      columns: columns.map(column => (column.name, column.col)),
      col_of,
      input_of: Map::from_array(
        inputs.mapi((index, column) => (column.name, index)),
      ),
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
    write_footer(
      entries,
      scope,
      keys=[],
      members=(0).until(data.length()).collect(),
      row=body_last + 1,
    )
    |> ignore
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
) -> Map[String, Int] raise @diag.SchemaError {
  let col_of : Map[String, Int] = Map([])
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
  col_of : Map[String, Int],
  body_first~ : Int,
  body_last~ : Int,
  banded~ : Map[Int, String],
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
  let mut field = None
  let mut formula = None
  let mut conditional = None
  let band = []
  for entry in entries {
    let (key, value) = entry
    match key {
      "name" => ()
      "header" => header = Some(value)
      "field" =>
        field = Some(expect_string(value, file~, context="\{where_} 'field'"))
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
  guard !(field is Some(_) && formula is Some(_)) else {
    raise schema_error(
      file~,
      "\{where_} has both a 'field' and a 'formula'; a formula column takes no data",
    )
  }
  { name, col, header, scope: None, field, formula, conditional, band, }
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
/// Replace each `{{name}}` in a formula with that column's cell in `row`. A
/// bare name inside a block instance (`scope`) means the instance's column first.
fn expand_column_refs(
  text : String,
  columns : Map[String, Int],
  row~ : Int,
  scope? : String,
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  substitute_names(text, in_formula=true, file~, context="\{context} formula", name => {
    let found = match scope {
      Some(instance) if !name.contains(".") &&
        columns.get("\{instance}.\{name}") is Some(col) => Some(col)
      _ => columns.get(name)
    }
    guard found is Some(col) else {
      let known = columns.keys().map(k => "'\{k}'").collect()
      raise schema_error(
        file~,
        "\{context} formula refers to '{{\{name}}}', which is not a column of this layout (\{or_list(known)})",
      )
    }
    @units.CellRef(col~, row~).to_a1()
  })
}

///|
/// Replace each `{{name}}` in `text` with what `replace` makes of the name. In a
/// formula, a `"…"` string literal is skipped (`""` escapes a quote).
fn substitute_names(
  text : String,
  in_formula~ : Bool,
  file~ : String,
  context~ : String,
  replace : (String) -> String raise @diag.SchemaError,
) -> String raise @diag.SchemaError {
  let chars = text.to_array()
  let out = StringBuilder()
  let mut quoted = false
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if in_formula && ch == '"' {
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
        raise schema_error(file~, "\{context} has a '{{' with no closing '}}'")
      }
      out.write_string(replace(String::from_array(chars[i + 2:end])))
      i = end + 2
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}
