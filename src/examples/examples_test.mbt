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
    // A duration is a plain number in the file: 36 hours is a day and a half.
    promise("quickstart.yxl.yaml", "Sales", "B6", "1.5"),
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
    // charts: the cells a chart plots are ordinary cells, which is the point.
    promise("charts.yxl.yaml", "Figures", "A2", "APAC"),
    promise("charts.yxl.yaml", "Figures", "C4", "2600000"),
    // pivots: likewise — the summary is Excel's work, the data is the spec's.
    promise("pivots.yxl.yaml", "Summary", "A1", "Revenue by region and quarter"),
    promise("pivots.yxl.yaml", "Orders", "D7", "3300000"),
    // shapes: the cells beneath the drawings are ordinary cells; the shapes
    // themselves are asserted separately below.
    promise("shapes.yxl.yaml", "Board", "A1", "Quarterly review"),
    promise("shapes.yxl.yaml", "Board", "B4", "2400000"),
  ]
}

///|
/// Read an included file through `@cli.resolve_path` — the same rule the CLI
/// applies, so the corpus exercises the real resolution instead of a copy.
fn included(from : String, path : String) -> @loader.Included raise {
  let name = @cli.resolve_path(from, path)
  { name, source: @fs.read_file_to_string(name) }
}

///|
/// The same, for a file the spec names but cannot hold as text: an image.
fn included_bytes(from : String, path : String) -> @loader.IncludedBytes raise {
  let name = @cli.resolve_path(from, path)
  { name, data: @fs.read_file_to_bytes(name) }
}

///|
test "every example compiles and holds what it promises" {
  for promise in promises() {
    let path = "\{EXAMPLES}/\{promise.spec}"
    let bytes = @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
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
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
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

  // Two notes, the second naming its author.
  let comments = workbook.get_comments("Orders")
  assert_eq(comments.length(), 2)
  assert_eq(comments[0].cell, "C3")
  assert_eq(comments[1].author, "Finance")

  // The sheet is locked but still sortable and filterable, and the cells the
  // form is filled in through are unlocked — which is what makes it a form.
  let protection = workbook.get_sheet_protection("Orders")
  assert_true(protection.sort)
  assert_true(protection.auto_filter)
  assert_false(protection.format_cells)
  guard workbook.get_cell_style("Orders", "B2") is Some(id) else {
    fail("expected a style on an entry cell")
  }
  assert_eq(workbook.get_style(id).protection.unwrap().locked, Some(false))
  assert_true(workbook.workbook_protection is Some(_))
}

///|
/// The `charts` example claims three charts, one of them plotting another
/// sheet. A chart is not a cell value, so the promise table cannot carry it.
test "the charts example draws what its comments describe" {
  let path = "\{EXAMPLES}/charts.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  guard workbook.sheet("Figures") is Some(figures) else {
    fail("expected the Figures sheet")
  }
  let charts = figures.charts()
  assert_eq(charts.length(), 2)
  assert_eq(charts[0].reference, "E2")
  assert_true(charts[0].xml.contains("<c:barChart>"))
  // Both series are named from their column headers, not written out.
  assert_true(charts[0].xml.contains("<c:f>'Figures'!$B$1</c:f>"))
  assert_true(charts[0].xml.contains("<c:f>'Figures'!$C$1</c:f>"))
  assert_eq(charts[1].reference, "E20")
  assert_true(charts[1].xml.contains("<c:pieChart>"))

  // The summary's chart plots the other sheet's cells rather than copying them.
  guard workbook.sheet("Summary") is Some(summary) else {
    fail("expected the Summary sheet")
  }
  assert_eq(summary.charts().length(), 1)
  let xml = summary.charts()[0].xml
  assert_true(xml.contains("<c:f>'Figures'!$B$2:$B$4</c:f>"))
  assert_false(xml.contains("<c:legend>"))
}

///|
/// The `pivots` example claims two summaries of one source. A pivot is not a
/// cell value either — and the file carries no summary at all, only the
/// instruction to build one — so it is asserted here.
test "the pivots example summarizes what its comments describe" {
  let path = "\{EXAMPLES}/pivots.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  let pivots = workbook.get_pivot_tables("Summary")
  assert_eq(pivots.length(), 2)
  assert_eq(pivots[0].name, "RevenueByRegion")
  assert_true(pivots[0].table_xml.contains("<location ref=\"A3:F30\""))
  assert_true(
    pivots[0].table_xml.contains("<pivotField name=\"Region\" axis=\"axisRow\""),
  )
  assert_true(
    pivots[0].table_xml.contains(
      "<pivotField name=\"Quarter\" axis=\"axisCol\"",
    ),
  )
  assert_true(
    pivots[0].table_xml.contains("name=\"Total revenue\" subtotal=\"sum\""),
  )
  // Both read the same source, and neither carries a cached summary: Excel
  // builds them on open.
  for pivot in pivots {
    assert_true(
      pivot.cache_definition_xml.contains(
        "<worksheetSource ref=\"A1:D7\" sheet=\"Orders\"/>",
      ),
    )
    assert_true(pivot.cache_definition_xml.contains("refreshOnLoad=\"1\""))
  }
  assert_true(pivots[1].table_xml.contains("subtotal=\"count\""))
  assert_true(pivots[1].table_xml.contains("colGrandTotals=\"0\""))
}

///|
/// The `modular` example claims the region its CSV fills arrives as an Excel
/// table. The table is not a cell value either, so it is asserted here.
test "the modular example declares its data region a table" {
  let path = "\{EXAMPLES}/modular.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  let tables = workbook.get_tables("Sales")
  assert_eq(tables.length(), 1)
  assert_eq(tables[0].name, "Revenue")
  assert_eq(tables[0].range_ref, "A1:B4")
  assert_eq(tables[0].style_name, "TableStyleMedium2")
  // The column names come from the header row the spec writes, not from the CSV
  // — the data starts at A2.
  assert_eq(tables[0].columns, ["Region", "Revenue"])
}

///|
/// The `layout` example claims to say what the file is and how Excel should
/// recalculate it. Neither is a cell value, so the promise table cannot carry
/// them either.
test "the layout example carries its document properties and calc mode" {
  let path = "\{EXAMPLES}/layout.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  let core = workbook.get_doc_props()
  assert_eq(core.title, "Regional summary")
  assert_eq(core.creator, "Finance team")
  assert_eq(core.content_status, "Final")
  assert_eq(workbook.get_app_props().company, "Example Ltd")
  let custom = workbook.get_custom_props()
  assert_eq(custom.length(), 2)
  assert_eq(custom[0].name, "Cost centre")
  assert_true(custom[0].value is Some(Integer(4210)))
  assert_true(custom[1].value is Some(Boolean(true)))
  let calc = workbook.get_calc_props()
  assert_eq(calc.calc_mode, Some("manual"))
  assert_eq(calc.full_calc_on_load, Some(true))

  // And the logo, whose bytes travelled from disk into the package.
  guard workbook.sheet("Summary") is Some(summary) else {
    fail("expected the Summary sheet")
  }
  let images = summary.images()
  assert_eq(images.length(), 1)
  assert_eq(images[0].reference, "E1")
  assert_eq(images[0].extension, "png")
  assert_eq(images[0].alt_text, "Example Ltd logo")
  assert_eq(
    images[0].data,
    @fs.read_file_to_bytes("\{EXAMPLES}/assets/logo.png"),
  )
}

///|
/// The `styling` example claims its conditional formats reuse the styles it
/// declares. Reuse is the point of the whole package (ADR-004), so it is worth
/// asserting rather than trusting.
test "the styling example's conditional formats share their declared looks" {
  let path = "\{EXAMPLES}/styling.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
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
/// The `shapes` example claims three drawings. A shape is not a cell value, so
/// the promise table cannot carry it.
test "the shapes example floats what its comments describe" {
  let path = "\{EXAMPLES}/shapes.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  guard workbook.sheet("Board") is Some(board) else {
    fail("expected the Board sheet")
  }
  let shapes = board.shapes()
  assert_eq(shapes.length(), 3)
  assert_eq(shapes[0].shape_type, "cloud")
  assert_eq(shapes[0].cell, "D1")
  assert_eq(shapes[0].fill_color, "D6E9F8")
  assert_eq(shapes[0].line_color, "1F77B4")
  assert_eq(shapes[0].paragraph[0].text, "Approved")
  assert_eq(shapes[0].format.alt_text, Some("An approval stamp"))
  // The chevron's two lines, in order.
  assert_eq(shapes[1].shape_type, "chevron")
  assert_eq(shapes[1].paragraph.map(run => run.text), ["Next", "quarter"])
  // The star is pinned to the sheet.
  assert_eq(shapes[2].shape_type, "star5")
  assert_true(shapes[2].format.positioning is Some(Absolute))
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
