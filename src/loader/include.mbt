// `$include` expansion: the pre-pass that turns a multi-file spec into the one
// document tree the schema loader sees. It runs before any schema key is
// interpreted, so an include may stand wherever a node may — a whole `cells:`
// block, one sheet, a `defs.styles` map — and every loader below this file stays
// unaware that more than one file existed (ADR-005).
//
// Reading the files is *not* done here: the loader takes a resolver and the CLI
// supplies one, so the compiler core stays I/O-free and tests run on in-memory
// files (ADR-003).

///|
/// The mapping key that marks an include. `$` marks it as a directive rather
/// than spec data, matching `$ref` (ADR-012); a YAML `!include` tag is not an
/// option, because the parser drops unknown tags silently, which would turn a
/// typo into a plain string instead of a diagnostic (ADR-010, ADR-014).
const INCLUDE_KEY : String = "$include"

///|
/// What an `$include` resolved to: the document's source text, and the name to
/// call it in diagnostics — the path the resolver actually opened, so an error
/// inside an included file points at that file, and a nested relative include
/// resolves against the right directory.
pub(all) struct Included {
  name : String
  source : String
}

///|
/// How the loader obtains an included document: given the name of the file
/// containing the `$include` and the path as written in it, return the source.
/// The CLI passes one that reads the disk; a test passes one backed by a map.
/// Failing to find or read the file should raise (a `@diag.SchemaError` names
/// the including file).
pub type IncludeResolver = (String, String) -> Included raise

///|
/// The resolver a caller that cannot read files gets. Reaching it means the spec
/// used `$include` in a context with no way to load one.
fn no_includes(from : String, path : String) -> Included raise {
  raise schema_error(
    file=from,
    "cannot resolve '\{INCLUDE_KEY}: \{path}' — this caller provides no way to read files",
  )
}

///|
/// What a binary file resolved to: its bytes, and the name to call it in
/// diagnostics — again the path the resolver actually opened.
pub(all) struct IncludedBytes {
  name : String
  data : Bytes
}

///|
/// How the loader obtains a file it cannot read as text — today only an image.
/// The same seam as `IncludeResolver` and for the same reason: the compiler core
/// opens nothing itself (ADR-003). Kept apart from it because a text resolver
/// has no bytes to give and a binary one no source text.
pub type BytesResolver = (String, String) -> IncludedBytes raise

///|
/// The binary resolver a caller that cannot read files gets. Reaching it means
/// the spec named an image in a context with no way to load one.
fn no_binaries(from : String, path : String) -> IncludedBytes raise {
  raise schema_error(
    file=from,
    "cannot read '\{path}' — this caller provides no way to read files",
  )
}

///|
/// Replace every `{ $include: path }` node with the document it names, itself
/// expanded. `chain` is the files currently being expanded, innermost last; it
/// both detects cycles and renders them.
fn expand_includes(
  node : @yaml.Node,
  file~ : String,
  resolve~ : IncludeResolver,
  chain~ : Array[String],
) -> @yaml.Node raise {
  match node {
    @yaml.Map([(key, value)]) if key == INCLUDE_KEY => {
      let path = expect_string(value, file~, context="'\{INCLUDE_KEY}'")
      let included = resolve(file, path)
      guard !chain.contains(included.name) else {
        raise cycle_error(chain, included.name, kind="include", file~)
      }
      // The included text is parsed here, not by the resolver, so a syntax error
      // in it is reported against the file it came from.
      let document = @yaml.parse(included.source, file=included.name)
      expand_includes(
        document,
        file=included.name,
        resolve~,
        chain=[..chain, included.name],
      )
    }
    @yaml.Map(entries) => {
      // An include replaces its whole node, so pairing it with siblings would
      // silently drop one or the other; say so rather than guess a merge.
      guard find_key(entries, INCLUDE_KEY) is None else {
        raise schema_error(
          file~,
          "'\{INCLUDE_KEY}' cannot be combined with other keys (it replaces the whole node)",
        )
      }
      let expanded = []
      for entry in entries {
        let (key, value) = entry
        expanded.push((key, expand_includes(value, file~, resolve~, chain~)))
      }
      @yaml.Map(expanded)
    }
    @yaml.Seq(items) => {
      let expanded = []
      for item in items {
        expanded.push(expand_includes(item, file~, resolve~, chain~))
      }
      @yaml.Seq(expanded)
    }
    scalar => scalar
  }
}
