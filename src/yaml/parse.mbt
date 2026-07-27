///|
/// Parse a single YAML document into a `Node` tree. `file` names the source in
/// diagnostics. A syntax error, or an unrepresentable value, raises a
/// `@diag.YamlError`. When the source holds more than one document, only the
/// first is used; an empty source is the null document.
///
/// A syntax error carries the line and column the parser stopped at. A *node*
/// carries none: the library exposes positions only on the error, not on the
/// tree it returns (ADR-010), so a diagnostic raised further down the pipeline —
/// an unknown key, a bad cell reference — names the file alone. Per-node spans
/// wait for a parser swap, which this seam keeps local.
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
    @yamllib.String(text) => Str(text)
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
        converted.push((key, convert(child, file)))
      }
      Map(converted)
    }
    @yamllib.BadValue =>
      raise @diag.YamlError(
        @diag.Diagnostic::new("\{file}: unrecognized or malformed YAML value"),
      )
  }
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
    @diag.Diagnostic::new(
      "invalid YAML: \{info}",
      span=@diag.Span::point(file, @diag.Pos::new(mark.line, mark.col + 1)),
    ),
  )
}
