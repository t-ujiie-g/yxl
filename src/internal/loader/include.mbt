///|
using @include {
  type Included,
  type IncludedBytes,
  type IncludeResolver,
  type BytesResolver,
}

///|
/// The key that marks an include, a `$` directive like `$ref` (ADR-012). Not a
/// YAML `!include` tag: the parser drops unknown tags silently (ADR-010,
/// ADR-014).
const INCLUDE_KEY : String = "$include"

///|
/// The resolver a caller that cannot read files gets. Reaching it means the
/// spec used `$include` in a context with no way to load one.
fn no_includes(from : String, path : String) -> Included raise {
  raise schema_error(
    file=from,
    "cannot resolve '\{INCLUDE_KEY}: \{path}' — this caller provides no way to read files",
  )
}

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
      // The included text is parsed here, not by the resolver, so a syntax
      // error in it is reported against the file it came from.
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
