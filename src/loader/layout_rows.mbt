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
    return load_layout_rows(key, value, inputs, file~, resolve~, context~)
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
  rows : Int?,
  data : Rows,
  has_source~ : Bool,
  file~ : String,
  context~ : String,
) -> Int raise @diag.SchemaError {
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
fn write_body_rows(
  sheet : @model.Sheet,
  data : Rows,
  inputs : Array[LayoutColumn],
  body_first~ : Int,
) -> Unit {
  for row_index, row in data {
    for field_index, value in row {
      if value is Some(value) {
        sheet.set(
          @units.CellRef(
            col=inputs[field_index].col,
            row=body_first + row_index,
          ),
          value,
        )
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
        picks.map(index => {
          match record.get(index) {
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
