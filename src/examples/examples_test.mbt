// Verification tier 2: the `examples/` corpus is the cookbook, so it has to keep
// working. Every `examples/*.yxl.yaml` is compiled here through the real
// pipeline and the result re-opened, so an example that stops producing what its
// comments claim fails the build rather than misleading a reader.
//
// `moon test` runs from the module root, so the paths below are the ones a
// reader would type. The on-disk include/data resolution the CLI does is
// exercised by `resolve_path`'s own test and by CI running the built binary over
// the same corpus.

///|
/// The directory holding the cookbook.
const EXAMPLES : String = "examples"

///|
/// One promise an example makes: after compiling `spec`, `sheet`!`cell` holds
/// `value` as the backend reads it back. `params` stands in for `--set`.
struct Promise {
  spec : String
  sheet : String
  cell : String
  value : String
  params : Map[String, String]
}

///|
/// Build a promise; most examples need no parameters.
fn promise(
  spec : String,
  sheet : String,
  cell : String,
  value : String,
  params? : Map[String, String] = Map([]),
) -> Promise {
  { spec, sheet, cell, value, params }
}

///|
/// What each example claims to produce. Adding an example without adding a
/// promise fails the coverage test below, so the corpus cannot quietly rot.
fn promises() -> Array[Promise] {
  [
    // quickstart: scalars keep YAML's types, a quoted number stays text, and a
    // formula carries its cached result.
    promise("quickstart.yxl.yaml", "Sales", "A2", "APAC"),
    promise("quickstart.yxl.yaml", "Sales", "B2", "2400000"),
    promise("quickstart.yxl.yaml", "Sales", "A4", "007"),
    promise("quickstart.yxl.yaml", "Sales", "B5", "4150000"),
    // styling: rich text reads back as its concatenated runs.
    promise("styling.yxl.yaml", "Report", "A1", "Region"),
    promise("styling.yxl.yaml", "Report", "B2", "2400000"),
    promise(
      "styling.yxl.yaml", "Report", "A8", "Figures are unaudited as of Q3.",
    ),
    // layout: the merged title survives, and the hidden sheet still holds text.
    promise("layout.yxl.yaml", "Summary", "A1", "Regional summary"),
    promise("layout.yxl.yaml", "Detail", "A1", "Everything above, in full."),
    // modular: these values come from the CSV and the JSON, not from the spec.
    promise("modular.yxl.yaml", "Sales", "A2", "APAC"),
    promise("modular.yxl.yaml", "Sales", "B4", "3100000"),
    promise("modular.yxl.yaml", "Sales", "D2", "closed"),
    // parameters: the defaults, then the same spec with `--set` applied.
    promise("parameters.yxl.yaml", "APAC", "A1", "Q3 APAC summary"),
    promise("parameters.yxl.yaml", "APAC", "B4", "Q3"),
    promise("parameters.yxl.yaml", "EMEA", "A1", "Q4 EMEA summary", params={
      "region": "EMEA",
      "quarter": "Q4",
    }),
  ]
}

///|
/// Read an included file relative to the spec that named it — the same rule the
/// CLI applies, so the corpus may split itself across directories.
fn included(from : String, path : String) -> @loader.Included raise {
  let name = match from.rev_find("/") {
    Some(slash) => from[:slash + 1].to_owned() + path
    None => path
  }
  { name, source: @fs.read_file_to_string(name) }
}

///|
test "every example compiles and holds what it promises" {
  for promise in promises() {
    let path = "\{EXAMPLES}/\{promise.spec}"
    let bytes = @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      params=promise.params,
    )
    let workbook = @xlsx.read(bytes[:])
    assert_eq(
      workbook.get_cell(promise.sheet, promise.cell),
      Some(promise.value),
    )
  }
}

///|
test "the corpus and the promises cover each other" {
  let promised = promises().map(promise => promise.spec)
  let specs = []
  for entry in @fs.read_dir(EXAMPLES) {
    // Sub-directories hold the files examples include; only the specs
    // themselves are compiled directly.
    if entry.has_suffix(".yxl.yaml") {
      specs.push(entry)
      // An example nothing asserts on is an example nothing protects.
      assert_true(promised.contains(entry))
    }
  }
  // And no promise names a spec that is not there.
  for promise in promises() {
    assert_true(specs.contains(promise.spec))
  }
  // A guard against both checks passing vacuously if the corpus were emptied.
  assert_true(specs.length() >= 5)
}
