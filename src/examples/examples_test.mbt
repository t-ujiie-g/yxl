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
    // interactive: the decorated cells keep their own values; what decorates
    // them is asserted separately below.
    promise("interactive.yxl.yaml", "Orders", "B2", "Sent"),
    promise("interactive.yxl.yaml", "Statuses", "A3", "Paid"),
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
/// The decorations are not cell values, so the promise table above cannot carry
/// them. This asserts the `interactive` example produces the filter, drop-downs,
/// and links its comments describe.
test "the interactive example decorates the cells it says it does" {
  let path = "\{EXAMPLES}/interactive.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(@fs.read_file_to_string(path), file=path, resolve=included)[:],
  )
  guard workbook.get_auto_filter("Orders") is Some(filter) else {
    fail("expected an auto filter over the header row")
  }
  assert_eq(filter.range_ref, "A1:D1")

  // Four validations, in the order the spec declares them.
  let validations = workbook.get_data_validations("Orders")
  assert_eq(validations.length(), 4)
  assert_eq(validations[0].sqref, "B2:B200")
  assert_eq(validations[0].validation_type, "list")
  // The drop-down reads its choices from the other sheet, absolutely.
  assert_eq(validations[0].formula1, "'Statuses'!$A$1:$A$3")
  assert_eq(validations[0].error_style, Some("stop"))
  assert_eq(validations[1].validation_type, "whole")
  assert_eq(validations[1].operator, "between")
  assert_false(validations[1].allow_blank)
  assert_eq(validations[2].validation_type, "date")
  // 2026-01-01 as a 1900-epoch serial.
  assert_eq(validations[2].formula1, "46023")
  assert_eq(validations[3].validation_type, "textLength")

  // One link out of the workbook, one into it.
  guard workbook.get_cell_hyperlink("Orders", "A2") is Some(external) else {
    fail("expected a link out of the workbook")
  }
  assert_eq(external.target, "https://example.com/orders/1001")
  guard workbook.get_cell_hyperlink("Orders", "B1") is Some(internal) else {
    fail("expected a link into the workbook")
  }
  assert_eq(internal.location, Some("Statuses!A1"))
  assert_eq(internal.tooltip, Some("The tracked statuses"))
}

///|
/// The `styling` example claims its conditional formats reuse the styles it
/// declares. Reuse is the point of the whole package (ADR-004), so it is worth
/// asserting rather than trusting.
test "the styling example's conditional formats share their declared looks" {
  let path = "\{EXAMPLES}/styling.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(@fs.read_file_to_string(path), file=path, resolve=included)[:],
  )
  let formats = workbook.get_conditional_formats("Report")
  guard formats.get("B2:B3") is Some(over_revenue) else {
    fail("expected conditional formats over B2:B3")
  }
  // Two highlighting rules and a data bar, in the order the spec declares them.
  assert_eq(over_revenue.length(), 3)
  assert_eq(over_revenue[0].criteria, "greater than or equal to")
  assert_eq(over_revenue[1].criteria, "less than")
  assert_true(over_revenue[1].stop_if_true)
  assert_eq(over_revenue[2].format_type, "data_bar")

  // The two highlighting rules wear different looks, and the data bar wears
  // none — it draws its own.
  assert_eq(over_revenue[0].format, Some(0))
  assert_eq(over_revenue[1].format, Some(1))
  assert_eq(over_revenue[2].format, None)
  assert_eq(formats.get("C2:C3").unwrap()[0].format_type, "3_color_scale")
  assert_eq(formats.get("D2:D3").unwrap()[0].icon_style, "3TrafficLights1")
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
