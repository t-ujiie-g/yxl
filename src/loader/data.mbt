///|
/// Where one table's rows come from. Exactly one form may be given per entry.
///
/// `Inline` is the odd one out: it is not a path but the rows themselves,
/// written in the spec. It exists for *diffs* — a `cells:` mapping is keyed by
/// address, so inserting a row rewrites every key below it and `git diff` calls
/// the whole block changed. Anchored rows move the addresses into one `at:`, so
/// inserting one is a one-line diff.
priv enum DataSource {
  Csv(String)
  Json(String)
  Inline(Rows)
}

///|
/// A table's cells, row-major. `None` is a blank cell — an empty CSV field or a
/// JSON `null` — which is left untouched rather than written as empty text.
type Rows = Array[Array[@model.CellValue?]]

///|
/// Load a sheet's `data:` sequence: each entry places a table with its top-left
/// field at `at`.
fn load_data(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  resolve~ : IncludeResolver,
) -> Unit raise {
  for item in expect_seq(node, file~, context="'data'") {
    load_data_entry(item, sheet, file~, resolve~)
  }
}

///|
/// One `data:` entry: `at` (the anchor), one source — `values:` for rows written
/// in the spec, `csv:` or `json:` for a path — and, for a JSON array of objects,
/// `columns:` naming the fields to take and their order.
fn load_data_entry(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  resolve~ : IncludeResolver,
) -> Unit raise {
  let entries = expect_map(node, file~, context="a 'data' entry")
  let anchor = anchor_cell(
    entries,
    file~,
    subject="a 'data' entry",
    noun="a 'data' entry",
  )
  let mut source = None
  let mut columns = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // the anchor, read above
      "csv" | "json" => {
        guard source is None else { raise one_source(file~) }
        let path = expect_string(value, file~, context="'data' '\{key}'")
        source = Some(if key == "csv" { Csv(path) } else { Json(path) })
      }
      "values" => {
        guard source is None else { raise one_source(file~) }
        source = Some(Inline(load_inline_rows(value, file~)))
      }
      "columns" => columns = Some(load_column_names(value, file~))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in a 'data' entry (expected 'at', 'csv', 'json', 'values', or 'columns')",
        )
    }
  }
  guard source is Some(source) else {
    raise schema_error(
      file~,
      "a 'data' entry needs a source: 'values' for rows written here, or 'csv' or 'json' for a file",
    )
  }
  let rows = match source {
    Csv(path) => {
      guard columns is None else {
        raise schema_error(
          file~,
          "'columns' names the fields of JSON objects; a CSV table's columns are its own",
        )
      }
      let table = resolve(file, path)
      parse_csv(table.source, file=table.name)
    }
    Json(path) => {
      let table = resolve(file, path)
      parse_json_table(table.source, file=table.name, columns~)
    }
    Inline(rows) => {
      guard columns is None else {
        raise schema_error(
          file~,
          "'columns' names the fields of JSON objects; inline rows are written in the order they should occupy",
        )
      }
      rows
    }
  }
  write_rows(sheet, anchor, rows)
}

///|
/// One entry, one source. Naming both a file and inline rows leaves no way to
/// say which wins, and guessing is what ADR-006 refuses.
fn one_source(file~ : String) -> @diag.SchemaError {
  schema_error(
    file~,
    "a 'data' entry sets more than one source (a table's rows come from one place: 'values', 'csv', or 'json')",
  )
}

///|
/// A `values:` block: a sequence of rows, each a sequence of scalars.
///
/// The scalars keep the types YAML gave them, so a quoted `"007"` stays text
/// and a bare `007` is the number 7 — the same rule a `cells:` value follows
/// (`docs/spec.md` §3), and a sharper one than CSV can offer, where every field
/// arrives as text and has to be guessed at.
///
/// `null` is a blank cell, left untouched rather than written as empty text —
/// matching a JSON table's `null` and a CSV's empty field.
fn load_inline_rows(
  node : @yaml.Node,
  file~ : String,
) -> Rows raise @diag.SchemaError {
  let rows : Rows = []
  for index, item in expect_seq(node, file~, context="'data' 'values'") {
    // Rows are 1-based in the message: the reader is looking at data, not code.
    let row_number = index + 1
    let values = []
    for
      field in expect_seq(
        item,
        file~,
        context="row \{row_number} of 'data' 'values'",
      ) {
      values.push(
        match field {
          @yaml.Null => None
          @yaml.Seq(_) | @yaml.Map(_) =>
            // Not `scalar_value`'s wording: `null` is admitted here and a
            // reader who reached this message needs to know that.
            raise schema_error(
              file~,
              "a field in row \{row_number} of 'data' 'values' must be text, a number, a boolean, or null for a blank cell",
            )
          _ =>
            Some(
              scalar_value(
                field,
                file~,
                context="a field in row \{row_number} of 'data' 'values'",
              ),
            )
        },
      )
    }
    rows.push(values)
  }
  rows
}

///|
/// A `columns:` list: the JSON object fields to take, in the order they should
/// occupy columns.
fn load_column_names(
  node : @yaml.Node,
  file~ : String,
) -> Array[String] raise @diag.SchemaError {
  let names = []
  for item in expect_seq(node, file~, context="'data' 'columns'") {
    names.push(expect_string(item, file~, context="a 'data' column name"))
  }
  names
}

///|
/// Write a table's rows into the sheet, the first field landing on `anchor`.
/// Rows need not be equal length; each starts again at the anchor's column.
fn write_rows(
  sheet : @model.Sheet,
  anchor : @units.CellRef,
  rows : Rows,
) -> Unit {
  for row_index, row in rows {
    for field_index, value in row {
      if value is Some(value) {
        sheet.set(
          @units.CellRef::new(
            col=anchor.col + field_index,
            row=anchor.row + row_index,
          ),
          value,
        )
      }
    }
  }
}

///|
/// Parse CSV (RFC 4180): fields separated by commas, records by newlines, a
/// field quoted with `"` may contain either and doubles an inner quote. `\r` is
/// tolerated so CRLF files load. A trailing newline ends the last record rather
/// than starting an empty one.
fn parse_csv(source : String, file~ : String) -> Rows raise @diag.SchemaError {
  let chars = source.iter().to_array()
  let rows : Rows = []
  let mut row : Array[@model.CellValue?] = []
  let field = StringBuilder::new()
  let mut in_quotes = false
  // Whether this field was quoted — a quoted field stays text, so a CSV can
  // carry "007" or "true" verbatim, mirroring YAML's quoting rule.
  let mut quoted = false
  // Whether anything (even a bare comma) has started the current record; without
  // it a trailing newline would add an empty row.
  let mut started = false
  fn end_field() -> Unit {
    row.push(csv_field(field.to_string(), quoted))
    field.reset()
    quoted = false
  }

  let mut index = 0
  while index < chars.length() {
    let ch = chars[index]
    if in_quotes {
      if ch == '"' {
        if index + 1 < chars.length() && chars[index + 1] == '"' {
          field.write_char('"')
          index += 2
          continue
        }
        in_quotes = false
      } else {
        field.write_char(ch)
      }
      index += 1
      continue
    }
    match ch {
      '"' => {
        in_quotes = true
        quoted = true
        started = true
      }
      ',' => {
        end_field()
        started = true
      }
      '\r' => () // half of a CRLF; the '\n' ends the record
      '\n' =>
        if started {
          end_field()
          rows.push(row)
          row = []
          started = false
        }
      _ => {
        field.write_char(ch)
        started = true
      }
    }
    index += 1
  }
  guard !in_quotes else {
    raise schema_error(file~, "CSV ends inside a quoted field")
  }
  if started {
    end_field()
    rows.push(row)
  }
  rows
}

///|
/// A CSV field as a cell value. A *quoted* field is always text; a bare one is
/// read as a number or boolean when it looks like one, and text otherwise —
/// CSV carries no types of its own, and this is the reading Excel gives an
/// imported file. A bare empty field is a blank cell.
fn csv_field(text : String, quoted : Bool) -> @model.CellValue? {
  if quoted {
    return Some(@model.Text(text))
  }
  match text {
    "" => None
    // The same reading a `--set` value gets: text that looks like a number or a
    // boolean is one.
    _ =>
      match infer_scalar(text) {
        @yaml.Bool(flag) => Some(@model.Bool(flag))
        @yaml.Float(number) => Some(@model.Number(number))
        _ => Some(@model.Text(text))
      }
  }
}

///|
/// Parse a JSON table: an array of rows, each an array of values, or an object
/// whose fields `columns` names and orders. JSON objects have no dependable key
/// order, so taking the fields in file order would make the layout depend on
/// something the format does not promise — hence `columns` is required there.
fn parse_json_table(
  source : String,
  file~ : String,
  columns~ : Array[String]?,
) -> Rows raise @diag.SchemaError {
  let document = @json.parse(source) catch {
    err => raise schema_error(file~, "invalid JSON: \{err}")
  }
  guard document is Array(items) else {
    raise schema_error(file~, "a JSON table must be an array of rows")
  }
  let rows : Rows = []
  for index, item in items {
    // Rows are 1-based in the message: the reader is looking at data, not code.
    let row_number = index + 1
    match item {
      Array(fields) => {
        guard columns is None else {
          raise schema_error(
            file~,
            "'columns' names the fields of JSON objects, but row \{row_number} is an array",
          )
        }
        let values = []
        for field in fields {
          values.push(json_field(field, file~, row=row_number))
        }
        rows.push(values)
      }
      Object(fields) => {
        guard columns is Some(names) else {
          raise schema_error(
            file~,
            "row \{row_number} is a JSON object, so 'columns' must name the fields to take (object key order is not dependable)",
          )
        }
        let values = []
        for name in names {
          guard fields.get(name) is Some(field) else {
            raise schema_error(
              file~,
              "row \{row_number} has no field '\{name}'",
            )
          }
          values.push(json_field(field, file~, row=row_number))
        }
        rows.push(values)
      }
      _ =>
        raise schema_error(
          file~,
          "row \{row_number} of a JSON table must be an array or an object",
        )
    }
  }
  rows
}

///|
/// One JSON value as a cell value; `null` is a blank cell. A nested array or
/// object has no cell to become.
fn json_field(
  value : Json,
  file~ : String,
  row~ : Int,
) -> @model.CellValue? raise @diag.SchemaError {
  match value {
    String(text) => Some(@model.Text(text))
    Number(number, ..) => Some(@model.Number(number))
    True => Some(@model.Bool(true))
    False => Some(@model.Bool(false))
    Null => None
    Array(_) | Object(_) =>
      raise schema_error(
        file~,
        "row \{row} has a field that is an array or object; a cell holds a string, number, boolean, or null",
      )
  }
}
