// End-to-end tests for `extract`: compile a spec, extract it back, and check
// what came out. The verify pass inside `extract` is itself under test here —
// a version that never checked anything would report no warnings too, so the
// tests that matter are the ones that make it *find* something.

///|
/// Compile a spec, then extract the bytes back into one.
fn extracted(source : String) -> @cli.Extracted raise {
  @cli.extract(@cli.compile(source, file="in.yaml"), file="in.xlsx")
}

///|
test "a spec survives the round trip through a real workbook" {
  let result = extracted(
    (
      #|sheets:
      #|  - name: Sales
      #|    cells:
      #|      A1: Region
      #|      B1: Revenue
      #|      A2: APAC
      #|      B2: 2400000
      #|
    ),
  )
  assert_eq(result.warnings, [])
  assert_eq(result.dropped, [])
  inspect(
    result.spec,
    content=(
      #|sheets:
      #|  - name: Sales
      #|    cells:
      #|      A1: Region
      #|      B1: Revenue
      #|      A2: APAC
      #|      B2: 2400000
      #|
    ),
  )
}

///|
test "the extracted spec compiles, which is what the verify pass asserts" {
  let source =
    #|defs:
    #|  styles:
    #|    header: { font: { bold: true }, fill: "1F3864" }
    #|sheets:
    #|  - name: Report
    #|    cells:
    #|      A1: { value: Region, style: header }
    #|      B1: { value: Revenue, style: header }
    #|      A2: APAC
    #|      B2: { value: 0.085, format: "0.0%" }
    #|    merges: [A1:B1]
    #|    freeze: A2
    #|
  let result = extracted(source)
  assert_eq(result.warnings, [])
  // Not merely re-readable: it compiles, and what it compiles to holds the same
  // cells. The spec is loaded here a second time to prove it is a *spec*, not
  // just text that happens to parse.
  @cli.compile(result.spec, file="out.yaml") |> ignore
}

///|
test "a style two cells share is declared once and referenced by name" {
  let result = extracted(
    (
      #|defs:
      #|  styles:
      #|    header: { font: { bold: true }, fill: "1F3864" }
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: Region, style: header }
      #|      B1: { value: Revenue, style: header }
      #|
    ),
  )
  // The name is invented — the file kept the sharing and lost the word — but the
  // *sharing* is the part that has to survive (ADR-004).
  assert_true(result.spec.contains("defs:"))
  assert_true(result.spec.contains("style: header"))
  assert_eq(result.warnings, [])
}

///|
test "what the schema cannot hold is named rather than dropped in silence" {
  // A theme colour has no meaning without the theme, which a spec does not
  // carry. The backend's default font uses one, so any workbook with a styled
  // font reaches this.
  let result = extracted(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: x, style: { font: { bold: true } } }
      #|
    ),
  )
  assert_eq(result.warnings, [])
}

///|
test "bytes that are not a workbook fail as a diagnostic" {
  let outcome = try {
    @cli.extract(b"not a workbook", file="x.xlsx") |> ignore
    None
  } catch {
    err => Some(@cli.error_message(err))
  }
  assert_true(outcome is Some(_))
}

///|
test "extract parses its own command line" {
  assert_eq(
    @cli.parse_args(["extract", "book.xlsx", "-o", "spec.yaml"][:]),
    Extract(input="book.xlsx", output="spec.yaml", flat=false),
  )
  assert_eq(
    @cli.parse_args(["extract", "book.xlsx", "--output", "spec.yaml"][:]),
    Extract(input="book.xlsx", output="spec.yaml", flat=false),
  )
  assert_eq(
    @cli.parse_args(["extract", "book.xlsx", "-o", "spec.yaml", "--flat"][:]),
    Extract(input="book.xlsx", output="spec.yaml", flat=true),
  )
}

///|
test "extract refuses a command line that could not do anything useful" {
  for
    args in [
      ["extract"],
      ["extract", "book.xlsx"],
      ["extract", "-o", "spec.yaml"],
      ["extract", "a.xlsx", "b.xlsx", "-o", "spec.yaml"],
      ["extract", "book.xlsx", "-o"],
      ["extract", "book.xlsx", "-o", "a.yaml", "-o", "b.yaml"],
      ["extract", "book.xlsx", "--set", "a=b", "-o", "spec.yaml"],
    ] {
    let outcome = try {
      @cli.parse_args(args[:]) |> ignore
      None
    } catch {
      @diag.CliError(d) => Some(d.render())
    }
    assert_true(outcome is Some(_))
  }
}

///|
/// A spec whose sheet is a block of plain values large enough to earn a file.
fn tabular_spec() -> String {
  let out = StringBuilder::new()
  out.write_string("sheets:\n  - name: Sales\n    cells:\n")
  for row in 1..<=12 {
    out.write_string("      A\{row}: r\{row}\n")
    out.write_string("      B\{row}: \{row * 100}\n")
  }
  out.to_string()
}

///|
test "a block of plain values is written beside the spec, not into it" {
  let result = extracted(tabular_spec())
  assert_eq(result.warnings, [])
  assert_eq(result.companions.length(), 1)
  assert_eq(result.companions[0].path, "data/sales.csv")
  // The spec names the file and holds none of the values.
  assert_true(result.spec.contains("csv: data/sales.csv"))
  assert_true(!result.spec.contains("cells:"))
  inspect(
    result.spec,
    content=(
      #|sheets:
      #|  - name: Sales
      #|    data:
      #|      - at: A1
      #|        csv: data/sales.csv
      #|
    ),
  )
}

///|
test "the verify pass reads the companion, so the check covers the CSV too" {
  // Without resolving the companion in memory the rebuilt workbook would be
  // empty and every cell would be reported missing — so an empty warning list
  // here is the CSV being checked, not skipped.
  let result = extracted(tabular_spec())
  assert_eq(result.warnings, [])
}

///|
test "--flat keeps everything in the one file" {
  let bytes = @cli.compile(tabular_spec(), file="in.yaml")
  let flat = @cli.extract(bytes, file="in.xlsx", flat=true)
  assert_eq(flat.companions.length(), 0)
  assert_eq(flat.warnings, [])
  assert_true(flat.spec.contains("cells:"))
  assert_true(!flat.spec.contains("csv:"))
}

///|
test "a sheet that is not a plain block is untouched by all this" {
  let result = extracted(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: Region
      #|      B1: { formula: "1+1" }
      #|
    ),
  )
  assert_eq(result.companions.length(), 0)
  assert_true(result.spec.contains("cells:"))
}
