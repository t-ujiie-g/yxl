///|
/// Parse then load, returning the diagnostic message if loading fails. `files`
/// backs any `$include` in the source.
fn schema_message(
  source : String,
  files? : Map[String, String] = Map([]),
  binaries? : Map[String, Bytes] = Map([]),
  params? : Map[String, String] = Map([]),
) -> String? raise {
  let document = @yaml.parse(source, file="spec.yaml")
  try {
    @loader.load(
      document,
      file="spec.yaml",
      resolve=memory_files(files),
      read_bytes=memory_binaries(binaries),
      params~,
    )
    |> ignore
    None
  } catch {
    @diag.SchemaError(d) | @diag.YamlError(d) => Some(d.render())
    other => Some(other.to_string())
  }
}

///|
/// Parse then load a spec expected to be valid. `files` backs any `$include`;
/// `params` stands in for the CLI's `--set`.
fn load_ok(
  source : String,
  files? : Map[String, String] = Map([]),
  binaries? : Map[String, Bytes] = Map([]),
  params? : Map[String, String] = Map([]),
) -> @model.Workbook raise {
  @loader.load(
    @yaml.parse(source, file="spec.yaml"),
    file="spec.yaml",
    resolve=memory_files(files),
    read_bytes=memory_binaries(binaries),
    params~,
  )
}

///|
/// An include resolver over an in-memory file map: the loader resolves includes
/// without touching the disk (ADR-003), so these tests need no fixtures.
fn memory_files(files : Map[String, String]) -> @loader.IncludeResolver {
  (_from, path) => {
    match files.get(path) {
      Some(source) => { name: path, source }
      None =>
        raise @diag.SchemaError(
          @diag.Diagnostic::new("no such included file '\{path}'"),
        )
    }
  }
}

///|
/// The same, for the files a spec cannot hold as text: an image's bytes.
fn memory_binaries(files : Map[String, Bytes]) -> @loader.BytesResolver {
  (_from, path) => {
    match files.get(path) {
      Some(data) => { name: path, data }
      None =>
        raise @diag.SchemaError(@diag.Diagnostic::new("no such file '\{path}'"))
    }
  }
}

///|
test "load rejects an unknown top-level key" {
  assert_eq(
    schema_message("sheetz:\n  - name: S\n"),
    Some(
      "spec.yaml: unknown top-level key 'sheetz' (expected 'sheets', 'active', 'params', 'date1904', 'default_font', 'defs', 'properties', 'calc', or 'protect')",
    ),
  )
}

///|
test "load requires the sheets key" {
  assert_eq(
    schema_message("title: report\n"),
    Some(
      "spec.yaml: unknown top-level key 'title' (expected 'sheets', 'active', 'params', 'date1904', 'default_font', 'defs', 'properties', 'calc', or 'protect')",
    ),
  )
  assert_eq(
    schema_message("{}\n"),
    Some("spec.yaml: missing required key 'sheets'"),
  )
}

///|
test "load requires each sheet to have a name" {
  assert_eq(
    schema_message("sheets:\n  - cells:\n      A1: x\n"),
    Some("spec.yaml: a sheet is missing required key 'name'"),
  )
}

///|
test "load rejects duplicate sheet names" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n  - name: S\n"),
    Some("spec.yaml: duplicate sheet name 'S'"),
  )
}

///|
test "load rejects an unknown key inside a sheet" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    color: red\n"),
    Some(
      "spec.yaml: unknown key 'color' in sheet (expected 'name', 'cells', 'data', 'columns', 'rows', 'merges', 'visibility', 'freeze', 'split', 'gridlines', 'tab_color', 'print', 'filter', 'validations', 'links', 'conditional', 'comments', 'tables', 'charts', 'images', 'shapes', 'background', 'sparklines', 'controls', 'pivots', or 'protect')",
    ),
  )
}
