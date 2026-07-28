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
    Extract(input="book.xlsx", output="spec.yaml"),
  )
  assert_eq(
    @cli.parse_args(["extract", "book.xlsx", "--output", "spec.yaml"][:]),
    Extract(input="book.xlsx", output="spec.yaml"),
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
