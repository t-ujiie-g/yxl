// Subdomain error types, one per pipeline stage (AGENTS.md §7). Each wraps a
// `Diagnostic` so failures share a single source-located shape, and each stage
// raises its own type — never a raw `String` — so a `catch` can tell where a
// failure came from. Constructors are public: pattern-match `YamlError(d)` to
// reach the wrapped diagnostic.

///|
/// A failure in the `yaml` stage: the source is not well-formed YAML.
pub(all) suberror YamlError {
  YamlError(Diagnostic)
} derive(Eq, Debug)

///|
/// A failure in the `loader` stage: the document parsed as YAML but violates the
/// `yxl` schema (unknown key, wrong type, missing required field).
pub(all) suberror SchemaError {
  SchemaError(Diagnostic)
} derive(Eq, Debug)

///|
/// A failure in the `resolve` stage: a named reference is dangling or cyclic.
pub(all) suberror ResolveError {
  ResolveError(Diagnostic)
} derive(Eq, Debug)

///|
/// A failure in the `emit` stage: the model could not be turned into `.xlsx`
/// bytes (typically surfaced from the backend behind the emitter seam).
pub(all) suberror EmitError {
  EmitError(Diagnostic)
} derive(Eq, Debug)

///|
/// A failure in the `cli` stage: bad arguments, or a file could not be read or
/// written. This is the only error tied to filesystem I/O (ADR-003).
pub(all) suberror CliError {
  CliError(Diagnostic)
} derive(Eq, Debug)
