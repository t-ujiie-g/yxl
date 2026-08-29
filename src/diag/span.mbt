///|
/// A 1-based line/column position within a source file. Line 1, column 1 is the
/// first character; this matches how editors and the ECMA-376 tooling report
/// locations, so a `yxl` diagnostic can be clicked straight to the source.
pub struct Pos {
  line : Int
  col : Int
} derive(Eq, Debug)

///|
/// Build a position from a 1-based line and column.
pub fn Pos::new(line : Int, col : Int) -> Pos {
  { line, col, }
}

///|
/// A source span: a file path plus the start and end positions of a region.
/// `start == end` marks a single point (a zero-width span). Higher packages
/// attach a `Span` to every diagnostic they raise (ADR-006).
pub struct Span {
  file : String
  start : Pos
  end : Pos
} derive(Eq, Debug)

///|
/// Build a span covering `start`..`end` within `file`.
pub fn Span::new(file : String, start : Pos, end : Pos) -> Span {
  { file, start, end, }
}

///|
/// A zero-width span at a single position (`start == end`) — used when a
/// diagnostic points at one spot rather than a range.
pub fn Span::point(file : String, at : Pos) -> Span {
  { file, start: at, end: at, }
}

///|
/// Render the span's start as `file:line:col`, the conventional location prefix
/// an editor can jump to. The end position is carried for future caret
/// rendering but not shown here.
pub fn Span::render(self : Span) -> String {
  "\{self.file}:\{self.start.line}:\{self.start.col}"
}
