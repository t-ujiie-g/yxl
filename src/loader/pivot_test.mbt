// Schema tests for a sheet's `pivots:`.

///|
/// A `Summary` sheet carrying `body`, and an `Orders` sheet with four named
/// columns over two rows for a pivot to summarize.
fn pivot_spec(body : String) -> String {
  "sheets:\n  - name: S\n    pivots:\n" +
  body +
  "  - name: Orders\n    cells:\n      A1: Region\n      B1: Quarter\n      C1: Channel\n      D1: Revenue\n" +
  "      A2: APAC\n      B2: Q3\n      C2: Direct\n      D2: 2400000\n" +
  "      A3: EMEA\n      B3: Q4\n      C3: Partner\n      D3: 1750000\n"
}

///|
/// The smallest pivot that loads.
const MINIMAL_PIVOT : String = "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values: [Revenue]\n"

///|
/// The sole pivot a spec loads.
fn loaded_pivot(body : String) -> @model.Pivot raise {
  let pivots = load_ok(pivot_spec(body)).sheets[0].pivots
  assert_eq(pivots.length(), 1)
  pivots[0]
}

///|
/// The diagnostic loading a pivot spec produces.
fn pivot_message(body : String) -> String? raise {
  schema_message(pivot_spec(body))
}

///|
test "a pivot loads its location, source, and axes" {
  let pivot = loaded_pivot(MINIMAL_PIVOT)
  assert_eq(pivot.at.top_left.to_a1(), "A1")
  assert_eq(pivot.at.bottom_right.to_a1(), "E20")
  assert_eq(pivot.source.sheet, Some("Orders"))
  assert_eq(pivot.source.range.bottom_right.to_a1(), "D3")
  assert_eq(pivot.rows, [{ field: "Region", name: None }])
  assert_eq(pivot.columns, [])
  // A bare name in `values:` sums, which is what Excel does with a numeric
  // field dropped there.
  assert_eq(pivot.values, [{ field: "Revenue", function: Sum, name: None }])
  assert_eq(pivot.name, None)
  assert_eq(pivot.style, None)
  // Excel shows both grand totals by default.
  assert_true(pivot.row_grand_totals)
  assert_true(pivot.column_grand_totals)
}

///|
test "a pivot loads every axis, name, style, and total" {
  let pivot = loaded_pivot(
    (
      #|      - at: A1:E20
      #|        source: Orders!A1:D3
      #|        rows: [Region]
      #|        columns:
      #|          - { field: Quarter, name: Period }
      #|        values:
      #|          - { field: Revenue, function: average, name: Mean revenue }
      #|        name: RevenueByRegion
      #|        style: PivotStyleMedium9
      #|        row_grand_totals: false
      #|        column_grand_totals: false
      #|
    ),
  )
  assert_eq(pivot.columns, [{ field: "Quarter", name: Some("Period") }])
  assert_eq(pivot.values, [
    { field: "Revenue", function: Average, name: Some("Mean revenue") },
  ])
  assert_eq(pivot.name, Some("RevenueByRegion"))
  assert_eq(pivot.style, Some("PivotStyleMedium9"))
  assert_false(pivot.row_grand_totals)
  assert_false(pivot.column_grand_totals)
}

///|
test "every aggregation a spec may name is accepted" {
  for
    function in [
      "sum", "count", "count_numbers", "average", "max", "min", "product", "std_dev",
      "std_dev_p", "var", "var_p",
    ] {
    assert_eq(
      pivot_message(
        "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values:\n          - { field: Revenue, function: \{function} }\n",
      ),
      None,
    )
  }
}

///|
test "an unknown aggregation is a diagnostic listing the ones there are" {
  guard pivot_message(
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values:\n          - { field: Revenue, function: median }\n",
    )
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_true(
    message.has_prefix(
      "spec.yaml: unknown pivot function 'median' in pivot 'A1:E20' 'values'",
    ),
  )
  assert_true(message.contains("'sum'"))
}

///|
test "a style outside Excel's set is a diagnostic naming the families" {
  assert_eq(
    pivot_message(
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values: [Revenue]\n        style: PivotStyleLight29\n",
    ),
    Some(
      "spec.yaml: unknown pivot style 'PivotStyleLight29' in pivot 'A1:E20' (expected 'PivotStyleLight1'-'PivotStyleLight28', 'PivotStyleMedium1'-'PivotStyleMedium28', 'PivotStyleDark1'-'PivotStyleDark28')",
    ),
  )
}

///|
test "a field the source does not have is a diagnostic naming the ones it does" {
  assert_eq(
    pivot_message(
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Territory]\n        values: [Revenue]\n",
    ),
    Some(
      "spec.yaml: pivot 'A1:E20' on sheet 'S' lays out field 'Territory', which its source does not have (it has Region, Quarter, Channel, Revenue)",
    ),
  )
}

///|
test "a source whose top row does not name every column is refused" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    pivots:\n      - at: D1:F20\n        source: A1:B3\n        rows: [Region]\n        values: [Revenue]\n" +
      "    cells:\n      A1: Region\n      A2: APAC\n      B2: 1\n",
    ),
    Some(
      "spec.yaml: pivot 'D1:F20' on sheet 'S' summarizes 'A1:B3', whose top row does not name every column, as text",
    ),
  )
}

///|
test "a source that is not a region with rows beneath a header is refused" {
  assert_eq(
    pivot_message(
      "      - at: A1:E20\n        source: Orders!A1:D1\n        rows: [Region]\n        values: [Revenue]\n",
    ),
    Some(
      "spec.yaml: pivot 'A1:E20' on sheet 'S' summarizes 'A1:D1', which is not a region with a header row and rows beneath it",
    ),
  )
}

///|
test "a pivot summarizing an undeclared sheet is a diagnostic" {
  assert_eq(
    pivot_message(
      "      - at: A1:E20\n        source: Missing!A1:D3\n        rows: [Region]\n        values: [Revenue]\n",
    ),
    Some(
      "spec.yaml: pivot 'A1:E20' on sheet 'S' summarizes sheet 'Missing', which is not declared",
    ),
  )
}

///|
test "a pivot drawn over its own source is a diagnostic" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    pivots:\n      - at: A1:E20\n        source: A1:D3\n        rows: [Region]\n        values: [Revenue]\n" +
      "    cells:\n      A1: Region\n      B1: Quarter\n      C1: Channel\n      D1: Revenue\n      A2: APAC\n",
    ),
    Some(
      "spec.yaml: pivot 'A1:E20' on sheet 'S' is drawn over the cells it summarizes at 'A1:D3'",
    ),
  )
}

///|
/// The backend splits `Sheet!A1:D7` on its first `!`, and Excel allows one in a
/// sheet name — such a pivot would summarize a sheet that does not exist.
test "a sheet name holding '!' is refused rather than silently mis-split" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: \"Wow!\"\n    cells:\n      A1: Region\n      B1: Revenue\n      A2: APAC\n      B2: 1\n" +
      "  - name: S\n    pivots:\n      - at: A1:E20\n        source: \"'Wow!'!A1:B2\"\n        rows: [Region]\n        values: [Revenue]\n",
    ),
    Some(
      "spec.yaml: pivot 'A1:E20' on sheet 'S' names sheet 'Wow!', and a pivot cannot reference a sheet whose name holds '!'",
    ),
  )
}

///|
/// Excel has a fourth axis, but the backend cannot write one Excel opens: the
/// `<location>` it emits leaves out the filter rows, and Excel answers `#SPILL!`.
/// Refused by name, with the reason, rather than left to look like a typo.
test "'filters' is refused, and says why" {
  assert_eq(
    pivot_message(
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values: [Revenue]\n        filters: [Channel]\n",
    ),
    Some(
      "spec.yaml: pivot 'A1:E20' sets 'filters', which the Excel backend cannot write in a form Excel opens — it leaves the filter rows out of the pivot's location, and Excel shows '#SPILL!' where the pivot should be",
    ),
  )
}

///|
/// The backend numbers every pivot's cache 1 while the workbook part numbers
/// them 1, 2, …, so a second pivot over another source would quietly summarize
/// the first one's data.
test "two pivots over different sources are refused" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    pivots:\n" +
      "      - at: A1:C10\n        source: A!A1:B3\n        rows: [Alpha]\n        values: [Num]\n" +
      "      - at: E1:G10\n        source: B!A1:B3\n        rows: [Beta]\n        values: [Val]\n" +
      "  - name: A\n    cells: { A1: Alpha, B1: Num, A2: x, B2: 1 }\n" +
      "  - name: B\n    cells: { A1: Beta, B1: Val, A2: p, B2: 3 }\n",
    ),
    Some(
      "spec.yaml: pivot 'E1:G10' on sheet 'S' summarizes 'B!A1:B3', but pivot 'A1:C10' on sheet 'S' summarizes 'A!A1:B3' — every pivot in a workbook must share one source, because the Excel backend gives them all the same cache and the later ones would quietly summarize the first one's data",
    ),
  )
}

///|
test "two pivots over one source are fine" {
  assert_eq(
    pivot_message(
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values: [Revenue]\n" +
      "      - at: A22:E40\n        source: Orders!A1:D3\n        rows: [Channel]\n        values: [Revenue]\n",
    ),
    None,
  )
}

///|
test "a pivot needs a location, a source, and something to lay out" {
  assert_eq(
    pivot_message(
      "      - source: Orders!A1:D3\n        rows: [Region]\n        values: [Revenue]\n",
    ),
    Some("spec.yaml: a pivot table is missing required key 'at'"),
  )
  assert_eq(
    pivot_message("      - at: A1:E20\n        rows: [Region]\n"),
    Some("spec.yaml: pivot 'A1:E20' is missing required key 'source'"),
  )
  assert_eq(
    pivot_message("      - at: A1:E20\n        source: Orders!A1:D3\n"),
    Some(
      "spec.yaml: pivot 'A1:E20' lays out no fields (expected 'rows', 'columns', or 'values')",
    ),
  )
}

///|
test "a pivot, an axis field, and a value field each reject an unknown key" {
  let cases = [
    (
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values: [Revenue]\n        layout: classic\n",
      "unknown key 'layout' in pivot 'A1:E20'",
    ),
    (
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows:\n          - { field: Region, sort: asc }\n        values: [Revenue]\n",
      "unknown key 'sort' in a pivot 'A1:E20' 'rows' field",
    ),
    (
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values:\n          - { field: Revenue, format: \"#,##0\" }\n",
      "unknown key 'format' in a pivot 'A1:E20' 'values' field",
    ),
  ]
  for entry in cases {
    let (body, expected) = entry
    guard pivot_message(body) is Some(message) else {
      fail("expected a diagnostic")
    }
    assert_true(message.has_prefix("spec.yaml: \{expected}"))
  }
}

///|
test "an axis field written as a mapping needs its 'field'" {
  assert_eq(
    pivot_message(
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows:\n          - { name: Territory }\n        values: [Revenue]\n",
    ),
    Some(
      "spec.yaml: a pivot 'A1:E20' 'rows' field is missing required key 'field'",
    ),
  )
  assert_eq(
    pivot_message(
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values:\n          - { function: sum }\n",
    ),
    Some(
      "spec.yaml: a pivot 'A1:E20' 'values' field is missing required key 'field'",
    ),
  )
}

///|
test "pivots keep their declaration order" {
  let wb = load_ok(
    pivot_spec(
      "      - at: A1:E20\n        source: Orders!A1:D3\n        rows: [Region]\n        values: [Revenue]\n        name: First\n" +
      "      - at: A22:E40\n        source: Orders!A1:D3\n        rows: [Quarter]\n        values: [Revenue]\n        name: Second\n",
    ),
  )
  let pivots = wb.sheets[0].pivots
  assert_eq(pivots.length(), 2)
  assert_eq(pivots[0].name, Some("First"))
  assert_eq(pivots[1].name, Some("Second"))
}
