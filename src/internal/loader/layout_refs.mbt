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
