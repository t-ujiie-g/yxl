///|
/// A YAML node — our type, not the parser library's, so the parser can be
/// swapped (ADR-010). Scalars arrive classified: bare `1` is `Int`, `"1"` `Str`.
pub(all) enum Node {
  Str(String)
  Int(Int64)
  Float(Double)
  Bool(Bool)
  Null
  Seq(Array[Node])
  Map(Array[(String, Node)])
} derive(Eq, Debug)
