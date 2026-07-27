// The YAML writer against the corpus. `src/yaml`'s own tests build nodes by
// hand, which proves the rules; these run the writer over every spec a real
// author wrote, which is what proves it on the shapes the schema actually takes.
//
// This is also a rehearsal of what `yxl extract` will do with its output
// (ADR-017): write a spec, then check it means what it was built from.

///|
/// Every spec in the corpus, by file name.
fn corpus() -> Array[String] {
  [
    "quickstart.yxl.yaml", "styling.yxl.yaml", "layout.yxl.yaml", "modular.yxl.yaml",
    "parameters.yxl.yaml", "charts.yxl.yaml", "pivots.yxl.yaml", "shapes.yxl.yaml",
    "sparklines.yxl.yaml", "interactive.yxl.yaml",
  ]
}

///|
test "every example survives being written back out as YAML" {
  for name in corpus() {
    let path = "\{EXAMPLES}/\{name}"
    let original = @yaml.parse(@fs.read_file_to_string(path), file=path)
    let rewritten = @yaml.parse(@yaml.write(original), file=path)
    // Not "close enough" — the same tree. Any quoting or indentation the writer
    // gets wrong shows up here as a changed node.
    assert_eq(rewritten, original)
  }
}

///|
test "a rewritten example still compiles to the same workbook" {
  // The stronger claim: the written form is not merely re-readable, it means the
  // same thing all the way to the bytes. `modular` and `parameters` are left out
  // — they reach for files and parameters that a bare re-parse does not carry.
  for
    name in [
      "quickstart.yxl.yaml", "styling.yxl.yaml", "charts.yxl.yaml", "pivots.yxl.yaml",
      "shapes.yxl.yaml", "sparklines.yxl.yaml", "interactive.yxl.yaml",
    ] {
    let path = "\{EXAMPLES}/\{name}"
    let source = @fs.read_file_to_string(path)
    let rewritten = @yaml.write(@yaml.parse(source, file=path))
    let from_original = @cli.compile(
      source,
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )
    let from_rewritten = @cli.compile(
      rewritten,
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )
    assert_eq(from_rewritten, from_original)
  }
}
