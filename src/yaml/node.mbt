///|
/// A YAML document node — the tree the parser seam hands to the loader. This is
/// *our* type, not the parser library's, so the pipeline never depends on the
/// backend parser directly and it can be swapped or vendored later — e.g. to add
/// source spans, whose event API the current library seals off (ADR-010).
///
/// Scalars arrive already classified by the parser (a bare `1` is `Int`, a
/// quoted `"1"` is `Str`), which is exactly the text-vs-number distinction the
/// loader wants.
pub(all) enum Node {
  Str(String)
  Int(Int64)
  Float(Double)
  Bool(Bool)
  Null
  Seq(Array[Node])
  Map(Array[(String, Node)])
} derive(Eq, Debug)
