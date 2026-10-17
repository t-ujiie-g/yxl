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
              typed_field(
                value,
                type_,
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
  type_ : ColumnType?
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
          let style = match default_format(input.type_, value) {
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
/// A layout column's `type`: what each of its fields is read as.
priv enum ColumnType {
  Text
  Number
  Bool
  Date
  Duration
}

///|
fn load_column_type(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> ColumnType raise @diag.SchemaError {
  match expect_string(node, file~, context="\{context} 'type'") {
    "text" => Text
    "number" => Number
    "bool" => Bool
    "date" => Date
    "duration" => Duration
    other =>
      raise schema_error(
        file~,
        "unknown type '\{other}' for \{context} (expected 'text', 'number', 'bool', 'date', or 'duration')",
      )
  }
}

///|
/// One field read as its column's `type`, as a `type:` on a cell reads its value
/// (`docs/spec.md` §3). `place` names the field in a diagnostic.
fn typed_field(
  value : @model.CellValue,
  type_ : ColumnType,
  file~ : String,
  place~ : String,
) -> @model.CellValue raise @diag.SchemaError {
  let text = match value {
    Text(text) => Some(text)
    _ => None
  }
  match (type_, value) {
    (Text, Text(_)) => value
    (Text, Number(number)) => Text(number.to_string())
    (Text, Bool(flag)) => Text(if flag { "true" } else { "false" })
    (Number, Number(_)) => value
    (Number, Text(text)) =>
      Number(
        @string.parse_double(text) catch {
          _ => raise schema_error(file~, "\{place} is not a number: '\{text}'")
        },
      )
    (Bool, Bool(_)) => value
    (Bool, Text("true")) => Bool(true)
    (Bool, Text("false")) => Bool(false)
    (Date, Text(text)) =>
      match @units.DateTime::parse(text) {
        Some(datetime) => Date(datetime)
        None =>
          raise schema_error(file~, "\{place} is not a valid date: '\{text}'")
      }
    (Duration, Text(text)) =>
      match @units.Duration::parse(text) {
        Some(duration) => Number(duration.to_serial())
        None =>
          raise schema_error(
            file~,
            "\{place} is not a valid duration: '\{text}' (expected H:MM or H:MM:SS, hours unbounded)",
          )
      }
    _ =>
      raise schema_error(
        file~,
        "\{place} cannot be read as \{type_name(type_)}: '\{text.unwrap_or(render_plain(value))}'",
      )
  }
}

///|
fn type_name(type_ : ColumnType) -> String {
  match type_ {
    Text => "text"
    Number => "a number"
    Bool => "a boolean"
    Date => "a date"
    Duration => "a duration"
  }
}

///|
fn render_plain(value : @model.CellValue) -> String {
  match value {
    Number(number) => number.to_string()
    Bool(flag) => if flag { "true" } else { "false" }
    _ => ""
  }
}

///|
/// The number format a typed cell takes when its column sets none, as a typed
/// cell's does (`docs/spec.md` §3).
fn default_format(type_ : ColumnType?, value : @model.CellValue) -> String? {
  match (type_, value) {
    (Some(Date), Date(datetime)) =>
      Some(
        if datetime.has_time() {
          DEFAULT_DATETIME_FORMAT
        } else {
          DEFAULT_DATE_FORMAT
        },
      )
    (Some(Duration), Number(_)) => Some(DEFAULT_DURATION_FORMAT)
    _ => None
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
