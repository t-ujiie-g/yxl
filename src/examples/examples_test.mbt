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
    promise("quickstart.yxl.yaml", "Sales", "A2", "APAC"),
    promise("quickstart.yxl.yaml", "Sales", "B2", "2400000"),
    promise("quickstart.yxl.yaml", "Sales", "A4", "007"),
    promise("quickstart.yxl.yaml", "Sales", "B5", "4150000"),
    promise("quickstart.yxl.yaml", "Sales", "B6", "1.5"),
    promise("quickstart.yxl.yaml", "Sales", "A9", "Quarter"),
    promise("quickstart.yxl.yaml", "Sales", "B12", "1300000"),
    promise("styling.yxl.yaml", "Report", "A1", "Region"),
    promise("styling.yxl.yaml", "Report", "B2", "2400000"),
    promise(
      "styling.yxl.yaml", "Report", "A8", "Figures are unaudited as of Q3.",
    ),
    promise("layout.yxl.yaml", "Summary", "A1", "Regional summary"),
    promise("layout.yxl.yaml", "Detail", "A1", "Everything above, in full."),
    promise("modular.yxl.yaml", "Sales", "A2", "APAC"),
    promise("modular.yxl.yaml", "Sales", "B4", "3100000"),
    promise("modular.yxl.yaml", "Sales", "D2", "closed"),
    promise("parameters.yxl.yaml", "APAC", "A1", "Q3 APAC summary"),
    promise("parameters.yxl.yaml", "APAC", "B4", "Q3"),
    promise("parameters.yxl.yaml", "EMEA", "A1", "Q4 EMEA summary", params={
      "region": "EMEA",
      "quarter": "Q4",
    }),
    promise("interactive.yxl.yaml", "Orders", "B2", "Sent"),
    promise("interactive.yxl.yaml", "Statuses", "A3", "Paid"),
    promise("charts.yxl.yaml", "Figures", "A2", "APAC"),
    promise("charts.yxl.yaml", "Figures", "C4", "2600000"),
    promise("pivots.yxl.yaml", "Summary", "A1", "Revenue by region and quarter"),
    promise("pivots.yxl.yaml", "Orders", "D7", "3300000"),
    promise("shapes.yxl.yaml", "Board", "A1", "Quarterly review"),
    promise("shapes.yxl.yaml", "Board", "B4", "2400000"),
    promise("sparklines.yxl.yaml", "Dashboard", "E2", "3100"),
    promise("sparklines.yxl.yaml", "Results", "C3", "1"),
    // An override wins over the `data:` row under it, and a style-only one
    // leaves the value the rules produced exactly where it was.
    promise("overrides.yxl.yaml", "Sales", "C4", "150"),
    promise("overrides.yxl.yaml", "Sales", "A4", "AMER"),
    promise("overrides.yxl.yaml", "Sales", "C3", "95"),
    promise("workbook.yxl.yaml", "Summary", "A1", "Store revenue — 2026-07"),
    promise("workbook.yxl.yaml", "Masters", "B2", "Shinjuku"),
    promise("workbook.yxl.yaml", "Sales", "B2", "2400000"),
    // The month names the CSV the sheet reads, so a refresh is this flag and a
    // file dropped beside its siblings.
    promise("workbook.yxl.yaml", "Sales", "B2", "2510000", params={
      "month": "2026-08",
    }),
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

  let validations = workbook.get_data_validations("Orders")
  assert_eq(validations.length(), 4)
  assert_eq(validations[0].sqref, "B2:B200")
  assert_eq(validations[0].validation_type, "list")
  assert_eq(validations[0].formula1, "'Statuses'!$A$1:$A$3")
  assert_eq(validations[0].error_style, Some("stop"))
  assert_eq(validations[1].validation_type, "whole")
  assert_eq(validations[1].operator, "between")
  assert_false(validations[1].allow_blank)
  assert_eq(validations[2].validation_type, "date")
  // 2026-01-01 as a 1900-epoch serial.
  assert_eq(validations[2].formula1, "46023")
  assert_eq(validations[3].validation_type, "textLength")

  guard workbook.get_cell_hyperlink("Orders", "A2") is Some(external) else {
    fail("expected a link out of the workbook")
  }
  assert_eq(external.target, "https://example.com/orders/1001")
  guard workbook.get_cell_hyperlink("Orders", "B1") is Some(internal) else {
    fail("expected a link into the workbook")
  }
  // Sheet-qualified and quoted, as every reference yxl writes is: Excel reads
  // a hyperlink's location as a reference, and an unquoted name with a space
  // in it is not one.
  assert_eq(internal.location, Some("'Statuses'!A1"))
  assert_eq(internal.tooltip, Some("The tracked statuses"))

  let comments = workbook.get_comments("Orders")
  assert_eq(comments.length(), 2)
  assert_eq(comments[0].cell, "C3")
  assert_eq(comments[1].author, "Finance")

  let controls = workbook.get_form_controls("Orders")
  assert_eq(controls.length(), 2)
  assert_eq(controls[0].control_type, "CheckBox")
  assert_eq(controls[0].text, "Rush order")
  assert_eq(controls[0].cell_link, Some("G2"))
  assert_eq(controls[1].control_type, "SpinButton")
  assert_eq(controls[1].min_val, Some(1))
  assert_eq(controls[1].max_val, Some(5))
  assert_eq(controls[1].current_val, Some(3))

  let protection = workbook.get_sheet_protection("Orders")
  assert_true(protection.sort)
  assert_true(protection.auto_filter)
  assert_false(protection.format_cells)
  guard workbook.get_cell_style("Orders", "B2") is Some(id) else {
    fail("expected a style on an entry cell")
  }
  assert_eq(workbook.get_style(id).protection.unwrap().locked, Some(false))
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
  assert_true(charts[0].xml.contains("<c:f>'Figures'!$B$1</c:f>"))
  assert_true(charts[0].xml.contains("<c:f>'Figures'!$C$1</c:f>"))
  assert_eq(charts[1].reference, "E20")
  assert_true(charts[1].xml.contains("<c:pieChart>"))

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
  assert_eq(over_revenue.length(), 3)
  assert_eq(over_revenue[0].criteria, "greater than or equal to")
  assert_eq(over_revenue[1].criteria, "less than")
  assert_true(over_revenue[1].stop_if_true)
  assert_eq(over_revenue[2].format_type, "data_bar")

  assert_eq(over_revenue[0].format, Some(0))
  assert_eq(over_revenue[1].format, Some(1))
  assert_eq(over_revenue[2].format, None)
  assert_eq(formats.get("C2:C3").unwrap()[0].format_type, "3_color_scale")
  assert_eq(formats.get("D2:D3").unwrap()[0].icon_style, "3TrafficLights1")
}

///|
/// The `modular` example filters its table with a slicer. A slicer is not a
/// cell value, so the promise table cannot carry it.
test "the modular example slices the table it declares" {
  let path = "\{EXAMPLES}/modular.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  let slicers = workbook.get_slicers("Sales")
  assert_eq(slicers.length(), 1)
  assert_eq(slicers[0].name, "Region")
  assert_eq(slicers[0].table_name, "Revenue")
  assert_eq(slicers[0].caption, "Filter by region")
  assert_eq(slicers[0].width, 160)
  assert_eq(slicers[0].height, 140)
}

///|
/// The `layout` example tiles a watermark behind its summary. A background is
/// not a cell value, so the promise table cannot carry it.
test "the layout example carries its background" {
  let path = "\{EXAMPLES}/layout.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  guard workbook.sheet("Summary") is Some(summary) else {
    fail("expected the Summary sheet")
  }
  guard summary.sheet_background() is Some(background) else {
    fail("expected a background")
  }
  assert_eq(background.extension, "png")
  assert_true(background.data.length() > 0)
}

///|
/// The `sparklines` example claims two groups of two. A sparkline is not a
/// cell value, so the promise table cannot carry it.
test "the sparklines example draws its two groups" {
  let path = "\{EXAMPLES}/sparklines.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  guard workbook.sheet("Dashboard") is Some(dashboard) else {
    fail("expected the Dashboard sheet")
  }
  let groups = dashboard.sparkline_groups()
  assert_eq(groups.length(), 2)
  assert_true(groups[0].sparkline_type is Line)
  assert_eq(groups[0].sparklines.map(spark => spark.location), ["F2", "F3"])
  assert_eq(groups[0].options.markers, true)
  assert_eq(groups[0].options.high, true)
  assert_eq(groups[0].options.color_series.unwrap().rgb, Some("FF1F77B4"))
  assert_true(groups[1].sparkline_type is WinLoss)
  assert_eq(groups[1].options.display_x_axis, true)
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
  assert_eq(shapes[1].shape_type, "chevron")
  assert_eq(shapes[1].paragraph.map(run => run.text), ["Next", "quarter"])
  assert_eq(shapes[2].shape_type, "star5")
  assert_true(shapes[2].format.positioning is Some(Absolute))
}

///|
/// The `workbook` example exists for its *structure* — one master reached by
/// reference from everywhere instead of copied — and none of that is a cell
/// value the promise table can hold.
test "the workbook example holds its master once and points at it" {
  let path = "\{EXAMPLES}/workbook.yxl.yaml"
  let workbook = @xlsx.read(
    @cli.compile(
      @fs.read_file_to_string(path),
      file=path,
      resolve=included,
      read_bytes=included_bytes,
    )[:],
  )
  assert_false(workbook.get_sheet_visible("Masters"))
  let master_tables = workbook.get_tables("Masters")
  assert_eq(master_tables.length(), 1)
  assert_eq(master_tables[0].name, "StoreMaster")
  assert_eq(master_tables[0].range_ref, "A1:C5")
  assert_eq(master_tables[0].columns, ["store_code", "store_name", "region"])

  // No sheet holds a second copy of a store name: the two that show one
  // compute it from the table above.
  assert_eq(workbook.get_cell("Sales", "C2"), Some(""))
  assert_eq(workbook.get_cell("Summary", "A4"), Some(""))
  assert_eq(
    workbook.get_cell_formula("Summary", "A4"),
    Some("IFERROR(INDEX(StoreMaster[store_name], ROW()-3), \"\")"),
  )

  // The drop-down offers exactly the master's codes.
  let validations = workbook.get_data_validations("Sales")
  assert_eq(validations.length(), 1)
  assert_eq(validations[0].formula1, "'Masters'!$A$2:$A$5")
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
  for promise in promises() {
    assert_true(specs.contains(promise.spec))
  }
  // A guard against both checks passing vacuously if the corpus were emptied.
  assert_true(specs.length() >= 5)
}
