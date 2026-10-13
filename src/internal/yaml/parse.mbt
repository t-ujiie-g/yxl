///|
/// Parse the first YAML document of `source` (an empty one is null). Only a
/// syntax error carries a position: the library gives nodes none (ADR-010).
pub fn parse(source : String, file~ : String) -> Node raise @diag.YamlError {
  let documents = @yamllib.Yaml::load_from_string(source) catch {
    err => raise from_library_error(err, file)
  }
  match documents {
    [] => Null
    [first, ..] => convert(first, file)
  }
}

///|
/// Translate the parser library's value tree into our `Node`. `BadValue` marks a
/// scalar the parser could not represent; we fail fast rather than pass it on.
fn convert(value : @yamllib.Yaml, file : String) -> Node raise @diag.YamlError {
  match value {
    @yamllib.String(text) => Str(repair_escapes(text))
    @yamllib.Integer(number) => Int(number)
    @yamllib.Real(number, ..) => Float(number)
    @yamllib.Boolean(flag) => Bool(flag)
    @yamllib.Null => Null
    @yamllib.Array(items) => {
      let converted = []
      for item in items {
        converted.push(convert(item, file))
      }
      Seq(converted)
    }
    @yamllib.Map(entries) => {
      let converted = []
      for key, child in entries {
        converted.push((repair_escapes(key), convert(child, file)))
      }
      Map(converted)
    }
    @yamllib.BadValue =>
      raise @diag.YamlError(
        @diag.Diagnostic("\{file}: unrecognized or malformed YAML value"),
      )
  }
}

///|
/// Undo the parser's decoding of `\v`, `\f`, `\r` as U+11–U+13 (yaml.mbt#14).
/// Exact, since YAML forbids those raw; `\e` and `\ ` cannot be told apart.
fn repair_escapes(text : String) -> String {
  let mut needs_repair = false
  for ch in text {
    if ch is ('\u{11}' | '\u{12}' | '\u{13}') {
      needs_repair = true
      break
    }
  }
  guard needs_repair else { return text }
  let repaired = StringBuilder()
  for ch in text {
    repaired.write_char(
      match ch {
        '\u{11}' => '\u{0B}'
        '\u{12}' => '\u{0C}'
        '\u{13}' => '\u{0D}'
        other => other
      },
    )
  }
  repaired.to_string()
}

///|
/// Wrap a parser-library error as our own, keeping the position it found the
/// problem at. The library reports lines from 1 and columns from 0; a `Pos`
/// counts both from 1, the way an editor does.
fn from_library_error(
  err : @yamllib.YamlError,
  file : String,
) -> @diag.YamlError {
  let @yamllib.YamlError(mark~, info~) = err
  @diag.YamlError(
    @diag.Diagnostic(
      "invalid YAML: \{info}",
      span=@diag.Span::point(file, @diag.Pos(mark.line, mark.col + 1)),
    ),
  )
}
