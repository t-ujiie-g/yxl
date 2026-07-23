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
/// there is no span. This is the plain single-line form; carets and colour are
/// a CLI concern.
pub fn Diagnostic::render(self : Diagnostic) -> String {
  match self.span {
    Some(span) => "\{span.render()}: \{self.message}"
    None => self.message
  }
}
