///|
/// The usage-error message for a command line, or None if it parses.
fn usage_message(args : ArrayView[String]) -> String? {
  try {
    @cli.parse_args(args) |> ignore
    None
  } catch {
    @diag.CliError(d) => Some(d.render())
  }
}

///|
test "parse_args accepts build with input and -o output, in either order" {
  for
    args in [
      ["build", "in.yaml", "-o", "out.xlsx"],
      ["build", "-o", "out.xlsx", "in.yaml"],
      ["build", "--output", "out.xlsx", "in.yaml"],
    ] {
    guard @cli.parse_args(args) is Build(input~, output~) else {
      fail("expected a Build command")
    }
    assert_eq(input, "in.yaml")
    assert_eq(output, "out.xlsx")
  }
}

///|
test "parse_args rejects malformed command lines" {
  assert_eq(
    usage_message([]),
    Some("no command given (usage: yxl build <in.yaml> -o <out.xlsx>)"),
  )
  assert_eq(
    usage_message(["serve"]),
    Some("unknown command 'serve' (expected 'build')"),
  )
  assert_eq(
    usage_message(["build", "-o", "out.xlsx"]),
    Some("no input file given"),
  )
  assert_eq(
    usage_message(["build", "in.yaml"]),
    Some("no output file given (use -o <out.xlsx>)"),
  )
  assert_eq(
    usage_message(["build", "in.yaml", "-o"]),
    Some("'-o' needs a file argument"),
  )
  assert_eq(
    usage_message(["build", "a.yaml", "b.yaml", "-o", "o.xlsx"]),
    Some("more than one input file given"),
  )
  assert_eq(
    usage_message(["build", "in.yaml", "-o", "a.xlsx", "-o", "b.xlsx"]),
    Some("'-o' was given more than once"),
  )
  assert_eq(
    usage_message(["build", "in.yaml", "-x", "-o", "o.xlsx"]),
    Some("unknown option '-x'"),
  )
}

///|
test "compile turns a valid spec into .xlsx bytes" {
  let source =
    #|sheets:
    #|  - name: Sheet1
    #|    cells:
    #|      A1: hello
    #|
  let bytes = @cli.compile(source, file="spec.yaml")
  assert_true(bytes.length() > 0)
  assert_eq(bytes[0], b'P')
  assert_eq(bytes[1], b'K')
}

///|
/// Golden round-trip at the spec boundary: a YAML spec compiles to real `.xlsx`
/// bytes, and re-opening them with the backend reader yields exactly the cells
/// the spec declared — across text, number, and boolean.
test "golden: a spec round-trips through .xlsx to the declared cells" {
  let source =
    #|sheets:
    #|  - name: Sales
    #|    cells:
    #|      A1: Region
    #|      B1: 42
    #|      C1: true
    #|      A2: "007"
    #|  - name: Notes
    #|    cells:
    #|      A1: 3.5
    #|
  let reopened = @xlsx.read(@cli.compile(source, file="spec.yaml")[:])
  assert_eq(reopened.get_cell("Sales", "A1"), Some("Region"))
  assert_eq(reopened.get_cell("Sales", "B1"), Some("42"))
  assert_eq(reopened.get_cell("Sales", "C1"), Some("1")) // boolean -> "1"
  assert_eq(reopened.get_cell("Sales", "A2"), Some("007")) // quoted stays text
  assert_eq(reopened.get_cell("Notes", "A1"), Some("3.5"))
}

///|
test "golden: an expanded cell's number format survives to the workbook" {
  let source =
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: { value: 0.5, format: "0.00%" }
    #|
  let reopened = @xlsx.read(@cli.compile(source, file="spec.yaml")[:])
  assert_eq(reopened.get_cell_value("S", "A1", raw=false), Some("50.00%"))
}

///|
test "compile surfaces a schema error carrying the file name" {
  let caught = try {
    @cli.compile("title: x\n", file="spec.yaml") |> ignore
    None
  } catch {
    err => Some(@cli.error_message(err))
  }
  assert_eq(
    caught,
    Some("spec.yaml: unknown top-level key 'title' (expected 'sheets')"),
  )
}
