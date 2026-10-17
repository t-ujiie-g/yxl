///|
/// The keys a layout column reads itself; the rest are its band's (§4).
let layout_column_keys : Array[String] = [
  "name", "header", "field", "type", "formula", "conditional", "body_style",
]

///|
/// The keys a layout column passes to its column band.
let layout_band_keys : Array[String] = [
  "width", "style", "format", "hidden", "group",
]

///|
/// One column of a layout as written, before it is placed.
priv struct LayoutColumn {
  name : String
  col : Int32
  header : @yaml.Node?
  scope : String?
  field : String?
  type_ : ValueType?
  formula : @yaml.Node?
  conditional : @yaml.Node?
  body_style : @yaml.Node?
  band : Array[(String, @yaml.Node)]
}

///|
/// Split one layout column into what the layout reads and what its band reads.
fn load_layout_column(
  node : @yaml.Node,
  col~ : Int32,
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
  let mut type_ = None
  let mut formula = None
  let mut conditional = None
  let mut body_style = None
  let band = []
  for entry in entries {
    let (key, value) = entry
    match key {
      "name" => ()
      "header" => header = Some(value)
      "field" =>
        field = Some(expect_string(value, file~, context="\{where_} 'field'"))
      "type" =>
        type_ = Some(
          parse_value_type(
            expect_string(value, file~, context="\{where_} 'type'"),
            file~,
            context=where_,
            errors=false,
          ),
        )
      "formula" => formula = Some(value)
      "conditional" => conditional = Some(value)
      "body_style" => body_style = Some(value)
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
  guard !(type_ is Some(_) && formula is Some(_)) else {
    raise schema_error(
      file~,
      "\{where_} has both a 'type' and a 'formula'; a formula column takes no data",
    )
  }
  {
    name,
    col,
    header,
    scope: None,
    field,
    type_,
    formula,
    conditional,
    body_style,
    band,
  }
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
  guard is_name(name, dots=false) else {
    raise schema_error(
      file~,
      "column name '\{name}' in \{context} must be letters, digits and '_', not starting with a digit",
    )
  }
}

///|
/// Letters, digits and `_`, or any non-ASCII character, not starting with a
/// digit; `dots` also admits `.` after the first character.
fn is_name(name : String, dots~ : Bool) -> Bool {
  let chars = name.to_array()
  !chars.is_empty() &&
  !chars[0].is_ascii_digit() &&
  chars[0] != '.' &&
  chars
  .iter()
  .all(ch => {
    ch.is_ascii_alphabetic() ||
    ch.is_ascii_digit() ||
    ch == '_' ||
    !ch.is_ascii() ||
    (dots && ch == '.')
  })
}
