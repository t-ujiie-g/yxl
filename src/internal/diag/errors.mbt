///|
/// A failure in the `yaml` stage: the source is not well-formed YAML.
#derive(Eq, Debug)
pub(all) suberror YamlError {
  YamlError(Diagnostic)
}

///|
/// A failure in the `loader` stage: the document parsed as YAML but violates
/// the `yxl` schema (unknown key, wrong type, missing required field).
#derive(Eq, Debug)
pub(all) suberror SchemaError {
  SchemaError(Diagnostic)
}

///|
/// A failure in the `resolve` stage: a named reference is dangling or cyclic.
#derive(Eq, Debug)
pub(all) suberror ResolveError {
  ResolveError(Diagnostic)
}

///|
/// A failure in the `emit` stage: the model could not be turned into `.xlsx`
/// bytes (typically surfaced from the backend behind the emitter seam).
#derive(Eq, Debug)
pub(all) suberror EmitError {
  EmitError(Diagnostic)
}

///|
/// A failure in the `read` stage: an `.xlsx` is not a workbook, or holds
/// something the reader cannot make sense of. The mirror of `EmitError`
/// (ADR-017).
#derive(Eq, Debug)
pub(all) suberror ReadError {
  ReadError(Diagnostic)
}

///|
/// A failure in the `cli` stage: bad arguments, or a file could not be read or
/// written. This is the only error tied to filesystem I/O (ADR-003).
#derive(Eq, Debug)
pub(all) suberror CliError {
  CliError(Diagnostic)
}
