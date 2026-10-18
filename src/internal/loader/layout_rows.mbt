///|
/// The rows a layout's source holds, or none without a source — where a
/// column's `field:` would have nothing to read.
fn load_body_data(
  source : (String, @yaml.Node)?,
  columns : Array[LayoutColumn],
  inputs : Array[LayoutColumn],
  file~ : String,
  resolve~ : IncludeResolver,
  context~ : String,
) -> Rows raise {
  if source is Some((key, value)) {
    let rows = load_layout_rows(key, value, inputs, file~, resolve~, context~)
    return rows.mapi((index, row) => {
      row.mapi((field, value) => {
        match (inputs[field].type_, value) {
          (Some(type_), Some(value)) =>
            Some(
              type_.read(
                value,
                file~,
                place="row \{index + 1} of \{context} column '\{inputs[field].name}'",
              ),
            )
          _ => value
        }
      })
    })
  }
  for column in columns {
    if column.field is Some(_) {
      raise schema_error(
        file~,
        "\{context} column '\{column.name}' has a 'field' but the layout reads no 'csv' or 'json'",
      )
    }
  }
  []
}

///|
/// How many body rows: `rows:` when given, which may reserve more than the data
/// fills but never fewer, and otherwise as many as the data holds.
fn body_rows(
  rows : Int32?,
  data : Rows,
  has_source~ : Bool,
  file~ : String,
  context~ : String,
) -> Int32 raise @diag.SchemaError {
  match rows {
    Some(rows) => {
      guard rows >= data.length() else {
        raise schema_error(
          file~,
          "\{context} 'rows' is \{rows}, fewer than the \{data.length()} rows its data holds",
        )
      }
      rows
    }
    None if has_source => {
      guard !data.is_empty() else {
        raise schema_error(
          file~,
          "\{context} reads no rows from its data, and sets no 'rows' to reserve",
        )
      }
      data.length()
    }
    None =>
      raise schema_error(
        file~,
        "\{context} needs 'rows', or a 'values', 'csv', or 'json' to count them from",
      )
  }
}

///|
/// An input column as its body is written: where, in what look, and the type
/// whose default number format a cell needs when the column sets none.
priv struct BodyInput {
  col : Int32
  style : @model.Style?
  type_ : ValueType?
}

///|
fn write_body_rows(
  sheet : @model.Sheet,
  data : Rows,
  inputs : Array[BodyInput],
  body_first~ : Int32,
  rows~ : Int32,
) -> Unit {
  for row_index in 0..<rows {
    let row = data.get(row_index).unwrap_or([])
    for field_index, input in inputs {
      let at = @units.CellRef(col=input.col, row=body_first + row_index)
      match row.get(field_index) {
        Some(Some(value)) => {
          let style = match
            input.type_.bind(type_ => type_.default_format(value)) {
            Some(code) =>
              @model.Style::layer(
                input.style,
                Some(@model.Style::number_format(code)),
              )
            None => input.style
          }
          sheet.set(at, value, style?)
        }
        _ => if input.style is Some(style) { sheet.set(at, Blank, style~) }
      }
    }
  }
}

///|
/// A layout's `values:`, `csv:` or `json:` as rows over its input columns, by
/// position or by field name (`docs/spec.md` §25).
fn load_layout_rows(
  key : String,
  node : @yaml.Node,
  inputs : Array[LayoutColumn],
  file~ : String,
  resolve~ : IncludeResolver,
  context~ : String,
) -> Rows raise {
  fn field_of(column : LayoutColumn) -> String {
    column.field.unwrap_or(column.name)
  }

  fn positional(rows : Rows, source : String) -> Rows raise {
    for column in inputs {
      if column.field is Some(_) {
        raise schema_error(
          file~,
          "\{context} column '\{column.name}' has a 'field', but \{source} rows are matched by position",
        )
      }
    }
    for index, row in rows {
      guard row.length() <= inputs.length() else {
        raise schema_error(
          file~,
          "row \{index + 1} of \{context} has \{row.length()} fields, but the layout has \{inputs.length()} columns without a formula to take them",
        )
      }
    }
    rows
  }

  match key {
    "values" => positional(load_inline_rows(node, file~), "'values'")
    "csv" => {
      let path = expect_string(node, file~, context="\{context} 'csv'")
      let table = resolve(file, path)
      let records = parse_csv_fields(table.source, file=table.name)
      guard records is [header, .. body] else {
        raise schema_error(
          file=table.name,
          "a CSV read by a layout starts with a header row naming its fields, and this one is empty",
        )
      }
      let names = header.map(field => field.0)
      let picks = inputs.map(column => {
        guard names.search(field_of(column)) is Some(index) else {
          raise schema_error(
            file=table.name,
            "the header row has no field '\{field_of(column)}' for \{context} column '\{column.name}' (fields: \{or_list(names.map(name => "'\{name}'"))})",
          )
        }
        index
      })
      body.map(record => {
        picks.mapi((pick, index) => {
          match record.get(index) {
            // A typed column reads the field as written, so `007` stays text.
            Some(("", _)) if inputs[pick].type_ is Some(_) => None
            Some((text, _)) if inputs[pick].type_ is Some(_) => Some(Text(text))
            Some((text, quoted)) => csv_field(text, quoted)
            None => None
          }
        })
      })
    }
    _ => {
      let path = expect_string(node, file~, context="\{context} 'json'")
      let table = resolve(file, path)
      let document = @json.parse(table.source) catch {
        err => raise schema_error(file=table.name, "invalid JSON: \{err}")
      }
      let named = document is Array(items) &&
        items.iter().any(item => item is Object(_))
      if named {
        parse_json_table(
          table.source,
          file=table.name,
          columns=Some(inputs.map(field_of)),
        )
      } else {
        positional(
          parse_json_table(table.source, file=table.name, columns=None),
          "JSON array",
        )
      }
    }
  }
}

///|
/// Merge each `merge_equal` column's runs of equal values down the body, cut
/// wherever a `merge_equal` column left of it changes. Every covered cell keeps
/// its value, so a `SUMIFS` or a filter over the column still finds it.
fn merge_equal_runs(
  sheet : @model.Sheet,
  data : Rows,
  inputs : Array[LayoutColumn],
  body_first~ : Int32,
  file~ : String,
  context~ : String,
) -> Unit raise @diag.SchemaError {
  let value = (row : Int32, field : Int32) => {
    data[row].get(field).unwrap_or(None)
  }
  let outer : Array[Int32] = []
  for field, column in inputs {
    guard column.merge_equal else { continue }
    guard !data.is_empty() else {
      raise schema_error(
        file~,
        "\{context} column '\{column.name}' has 'merge_equal' but the layout reads no data to merge",
      )
    }
    let mut start = 0
    for row in 1..<=data.length() {
      let continues = row < data.length() &&
        value(row, field) is Some(_) &&
        value(row, field) == value(start, field) &&
        outer.all(left => value(row, left) == value(row - 1, left))
      if continues {
        continue
      }
      if row - start > 1 && value(start, field) is Some(_) {
        sheet.merge(
          @units.CellRef(col=column.col, row=body_first + start),
          @units.CellRef(col=column.col, row=body_first + row - 1),
        )
      }
      start = row
    }
    outer.push(field)
  }
}

///|
/// A page break above every body row whose `column` differs from the row
/// above it, so each run of one value starts a printed page.
fn break_pages_on(
  sheet : @model.Sheet,
  data : Rows,
  inputs : Array[LayoutColumn],
  column~ : String,
  body_first~ : Int32,
  file~ : String,
  context~ : String,
) -> Unit raise @diag.SchemaError {
  guard inputs.search_by(input => input.name == column) is Some(field) else {
    raise schema_error(
      file~,
      "\{context} 'page_break_on' names '\{column}', which is not a column the layout's data fills",
    )
  }
  guard !data.is_empty() else {
    raise schema_error(
      file~,
      "\{context} has 'page_break_on' but reads no data to break on",
    )
  }
  let value = (row : Int32) => data[row].get(field).unwrap_or(None)
  for row in 1..<data.length() {
    if value(row) != value(row - 1) {
      sheet.add_row_break(body_first + row)
    }
  }
}
