///|
/// Every spec in the corpus, by file name.
fn corpus() -> Array[String] {
  [
    "quickstart.yxl.yaml", "styling.yxl.yaml", "layout.yxl.yaml", "modular.yxl.yaml",
    "parameters.yxl.yaml", "charts.yxl.yaml", "pivots.yxl.yaml", "shapes.yxl.yaml",
    "sparklines.yxl.yaml", "interactive.yxl.yaml", "overrides.yxl.yaml",
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
      "shapes.yxl.yaml", "sparklines.yxl.yaml", "interactive.yxl.yaml", "overrides.yxl.yaml",
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

///|
test "every example extracts back into a spec that checks out" {
  // The corpus is the only place `extract` meets specs a person wrote rather
  // than ones a test built to suit it. The assertion is on the *self-check*: a
  // warning means the extracted spec does not rebuild what it was read from,
  // which is the one thing `extract` promises (ADR-017).
  for
    name in [
      "quickstart.yxl.yaml", "styling.yxl.yaml", "layout.yxl.yaml", "charts.yxl.yaml",
      "pivots.yxl.yaml", "shapes.yxl.yaml", "sparklines.yxl.yaml", "interactive.yxl.yaml",
      "overrides.yxl.yaml",
    ] {
    let path = "\{EXAMPLES}/\{name}"
    let bytes = @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )
    let extracted = @cli.extract(bytes, file=path)
    assert_eq((name, extracted.warnings), (name, []))
    let files : Map[String, Bytes] = Map([])
    for companion in extracted.companions {
      files[companion.path] = companion.content
    }
    @cli.compile(
      extracted.spec,
      file="extracted-\{name}",
      resolve=(_from, wanted) => {
        name: wanted,
        source: match files.get(wanted) {
          Some(content) => @utf8.decode_lossy(content[:])
          None => ""
        },
      },
      read_bytes=(_from, wanted) => {
        name: wanted,
        data: files.get(wanted).unwrap_or(b""),
      },
    )
    |> ignore
  }
}
