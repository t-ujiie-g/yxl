///|
/// One diagnostic: a human-readable message optionally anchored to a source
/// span. Every subdomain error (see `errors.mbt`) wraps a `Diagnostic`, so the
/// whole pipeline reports failures in one uniform, source-located shape.
pub struct Diagnostic {
  message : String
  span : Span?
} derive(Eq, Debug)

///|
/// Build a diagnostic. Pass `span=` to anchor it to a source location; omit it
/// for failures with no meaningful position (e.g. a CLI usage error).
pub fn Diagnostic::new(message : String, span? : Span) -> Diagnostic {
  { message, span }
}

///|
/// Render as `file:line:col: message` when anchored, or just `message` when
/// there is no span. This is the plain single-line form; `render_in` adds the
/// source line and a caret.
pub fn Diagnostic::render(self : Diagnostic) -> String {
  match self.span {
    Some(span) => "\{span.render()}: \{self.message}"
    None => self.message
  }
}

///|
/// Render with the offending source line quoted underneath and a caret marking
/// the column:
///
/// ```text
/// report.yaml:2:4: invalid YAML: mapping values are not allowed in this context
///   |
/// 2 |   c: d
///   |    ^
/// ```
///
/// `source` is the text the span's file was parsed from; a diagnostic with no
/// span, or one whose line is not in `source`, falls back to `render`. Callers
/// that have the source (the CLI does) should prefer this — the position alone
/// tells a reader where to look, but the quoted line tells them what is there.
pub fn Diagnostic::render_in(self : Diagnostic, source : String) -> String {
  guard self.span is Some(span) else { return self.message }
  let lines = source.split("\n").collect()
  let index = span.start.line - 1
  guard index >= 0 && index < lines.length() else { return self.render() }
  let text = lines[index].to_owned()
  // The gutter is as wide as the line number, so the bars line up under it.
  let number = span.start.line.to_string()
  let gutter = " ".repeat(number.length())
  let caret = " ".repeat(
      if span.start.col > 1 {
        span.start.col - 1
      } else {
        0
      },
    ) +
    "^"
  [self.render(), "\{gutter} |", "\{number} | \{text}", "\{gutter} | \{caret}"].join(
    "\n",
  )
}
