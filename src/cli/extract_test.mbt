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

///|
test "a picture is written beside the spec, and the spec names it" {
  let source =
    #|sheets:
    #|  - name: Summary
    #|    cells:
    #|      A1: x
    #|    images:
    #|      - at: E1
    #|        file: logo.png
    #|        alt: The logo
    #|    background: logo.png
    #|
  let png : Bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
  let bytes = @cli.compile(source, file="in.yaml", read_bytes=(_from, path) => {
    name: path,
    data: png,
  })
  let result = @cli.extract(bytes, file="in.xlsx")
  assert_eq(result.warnings, [])
  assert_eq(result.companions.length(), 2)
  let paths = result.companions.map(companion => companion.path)
  assert_eq(paths, ["assets/summary_e1.png", "assets/summary_background.png"])
  for companion in result.companions {
    assert_eq(companion.content, png)
  }
  assert_true(result.spec.contains("file: assets/summary_e1.png"))
  assert_true(result.spec.contains("background: assets/summary_background.png"))
}

///|
test "--flat leaves the tables inline but still writes the pictures" {
  // A picture has no inline form to fall back to, so `--flat` has nothing to
  // say about it.
  let png : Bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
  let bytes = @cli.compile(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: x
      #|    images:
      #|      - at: C1
      #|        file: logo.png
      #|
    ),
    file="in.yaml",
    read_bytes=(_from, path) => { name: path, data: png },
  )
  let flat = @cli.extract(bytes, file="in.xlsx", flat=true)
  assert_eq(flat.companions.length(), 1)
  assert_eq(flat.warnings, [])
}

///|
/// A spec exercising all four things that float over a sheet.
fn floating_spec() -> String {
  (
    #|sheets:
    #|  - name: Board
    #|    cells:
    #|      A1: Region
    #|      B1: Revenue
    #|      A2: APAC
    #|      B2: 2400000
    #|      A3: EMEA
    #|      B3: 1750000
    #|    tables:
    #|      - at: A1:B3
    #|        name: Revenue
    #|    shapes:
    #|      - at: D1
    #|        kind: cloud
    #|        text: Approved
    #|        size: { width: 220, height: 110 }
    #|        fill: "D6E9F8"
    #|        line: { color: "1F77B4", width: 2 }
    #|    sparklines:
    #|      - at: C2
    #|        data: A2:B3
    #|        markers: true
    #|        high: true
    #|    controls:
    #|      - at: F2
    #|        kind: check_box
    #|        text: Rush order
    #|        link: G2
    #|    slicers:
    #|      - at: H1
    #|        table: Revenue
    #|        column: Region
    #|        caption: Filter by region
    #|
  )
}

///|
test "the four things that float over a sheet come back as themselves" {
  let result = extracted(floating_spec())
  // The verify pass re-compiles the spec and compares, so an empty list here is
  // the extracted spec building the same workbook — not merely parsing.
  assert_eq(result.warnings, [])
  assert_true(result.spec.contains("kind: cloud"))
  assert_true(result.spec.contains("data: A2:B3"))
  assert_true(result.spec.contains("kind: check_box"))
  assert_true(result.spec.contains("column: Region"))
  // Two, and only two: a control's size and a shape text's font, which the
  // file records and the backend's reader does not hand back.
  assert_eq(result.dropped.length(), 2)
  assert_true(result.dropped[0].contains("any size on a form control"))
  assert_true(result.dropped[1].contains("any font on a line of shape text"))
}

///|
test "a slicer does not bring its own defined name back with it" {
  // The backend writes `Slicer_Region` as a defined name when it places a
  // slicer. Recovering that name *and* the slicer would make the spec ask for
  // it twice, and the second attempt is a hard error from the backend — so this
  // failing looks like `DefinedNameDuplicate`, not like a cosmetic extra key.
  let result = extracted(floating_spec())
  assert_true(!result.spec.contains("Slicer_"))
  @cli.compile(result.spec, file="out.yaml") |> ignore
}

///|
test "extracting twice gives the same spec" {
  // Compiling what came out and extracting *that* is the sharpest check of the
  // whole loop: anything the reader invents rather than recovers — an order,
  // a name, a default written down as if it were asked for — shows up as drift
  // on the second pass even when the first pass verified.
  let once = extracted(floating_spec())
  let twice = @cli.extract(
    @cli.compile(once.spec, file="out.yaml"),
    file="out.xlsx",
  )
  assert_eq(twice.spec, once.spec)
}
