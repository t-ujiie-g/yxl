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
    guard @cli.parse_args(args) is Build(input~, output~, ..) else {
      fail("expected a Build command")
    }
    assert_eq(input, "in.yaml")
    assert_eq(output, "out.xlsx")
  }
}

///|
test "parse_args rejects malformed command lines" {
  assert_eq(
    usage_message(["serve"]),
    Some(
      "unknown command 'serve' (expected 'build', 'extract', 'help', or 'version')",
    ),
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
test "parse_args collects repeated --set overrides" {
  guard @cli.parse_args([
      "build", "in.yaml", "-o", "out.xlsx", "--set", "region=EMEA", "--set", "rate=0.15",
      "--set", "note=",
    ])
    is Build(params~, ..) else {
    fail("expected a Build command")
  }
  assert_eq(params.get("region"), Some("EMEA"))
  assert_eq(params.get("rate"), Some("0.15"))
  // A value may be empty; only the name may not.
  assert_eq(params.get("note"), Some(""))
}

///|
test "parse_args rejects malformed --set arguments" {
  assert_eq(
    usage_message(["build", "in.yaml", "-o", "o.xlsx", "--set"]),
    Some("'--set' needs a 'name=value' argument"),
  )
  assert_eq(
    usage_message(["build", "in.yaml", "-o", "o.xlsx", "--set", "region"]),
    Some("'--set region' must be 'name=value'"),
  )
  assert_eq(
    usage_message(["build", "in.yaml", "-o", "o.xlsx", "--set", "=EMEA"]),
    Some("'--set =EMEA' has no parameter name"),
  )
  assert_eq(
    usage_message([
      "build", "in.yaml", "-o", "o.xlsx", "--set", "a=1", "--set", "a=2",
    ]),
    Some("'--set a=' was given more than once"),
  )
}

///|
/// Golden round-trip for a parameterized spec: one spec, two workbooks.
test "golden: --set overrides a declared parameter" {
  let source =
    #|params:
    #|  region: APAC
    #|  rate: 0.08
    #|sheets:
    #|  - name: "${region}"
    #|    cells:
    #|      A1: "Tax for ${region}"
    #|      B1: "${rate}"
    #|
  let default_build = @xlsx.read(@cli.compile(source, file="spec.yaml")[:])
  assert_eq(default_build.get_cell("APAC", "A1"), Some("Tax for APAC"))
  assert_eq(default_build.get_cell("APAC", "B1"), Some("0.08"))
  let overridden = @xlsx.read(
    @cli.compile(source, file="spec.yaml", params={
      "region": "EMEA",
      "rate": "0.2",
    })[:],
  )
  assert_eq(overridden.get_cell("EMEA", "A1"), Some("Tax for EMEA"))
  // The override stays a number cell, as the default was.
  assert_true(overridden.get_cell_value_raw("EMEA", "B1") is Some(Numeric(0.2)))
}

///|
test "parse_args recognises help, version, and --check" {
  // A bare `yxl` is a request for help, not an error.
  assert_eq(@cli.parse_args([]), Help)
  for spelling in ["help", "--help", "-h"] {
    assert_eq(@cli.parse_args([spelling]), Help)
  }
  for spelling in ["version", "--version", "-V"] {
    assert_eq(@cli.parse_args([spelling]), Version)
  }
  assert_eq(
    @cli.parse_args(["build", "in.yaml", "--check", "--set", "a=1"]),
    Check(input="in.yaml", params={ "a": "1" }),
  )
}

///|
test "parse_args rejects --check with an output path" {
  // `--check` writes nothing, so `-o` would promise a file that never appears.
  assert_eq(
    usage_message(["build", "in.yaml", "--check", "-o", "out.xlsx"]),
    Some("'--check' writes nothing, so it cannot take '-o'"),
  )
  // Without `--check`, an output is still required.
  assert_eq(
    usage_message(["build", "in.yaml"]),
    Some("no output file given (use -o <out.xlsx>)"),
  )
}

///|
test "the usage text lists every command and exit code" {
  // Help is what a bare `yxl` prints, so it must stay in step with the parser.
  for command in ["build", "help", "version"] {
    assert_true(@cli.usage.contains(command))
  }
  for option in ["-o", "--check", "--set"] {
    assert_true(@cli.usage.contains(option))
  }
  for code in ["0", "1", "2"] {
    assert_true(@cli.usage.contains("  \{code}  "))
  }
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
test "golden: a typed date compiles to an Excel serial with a date format" {
  let source =
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: { value: "2000-01-01", type: date }
    #|
  let reopened = @xlsx.read(@cli.compile(source, file="spec.yaml")[:])
  // The raw value is the 1900-system serial for 2000-01-01.
  assert_eq(reopened.get_cell_value("S", "A1", raw=true), Some("36526"))
  // And the default date format renders it back as the date.
  assert_eq(reopened.get_cell_value("S", "A1", raw=false), Some("2000-01-01"))
}

///|
test "golden: a typed duration compiles to a day fraction wearing an elapsed format" {
  let source =
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: { value: "36:00:00", type: duration }
    #|
  let reopened = @xlsx.read(@cli.compile(source, file="spec.yaml")[:])
  // A day and a half — a duration is a plain number in the file.
  assert_eq(reopened.get_cell_value("S", "A1", raw=true), Some("1.5"))
  // The `[h]` format keeps counting past 24 instead of rolling into days.
  assert_eq(reopened.get_cell_value("S", "A1", raw=false), Some("36:00:00"))
}

///|
test "golden: a formula cell round-trips as an <f> with its cached value" {
  let source =
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: 3
    #|      B1: 4
    #|      C1: { formula: "=A1+B1", value: 7 }
    #|
  let reopened = @xlsx.read(@cli.compile(source, file="spec.yaml")[:])
  assert_eq(reopened.get_cell_formula("S", "C1"), Some("A1+B1"))
  assert_eq(reopened.get_cell_value("S", "C1", raw=true), Some("7"))
}

///|
test "golden: explicit typing coerces the stored type, and errors survive" {
  let source =
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: { value: 42, type: text }
    #|      A2: { value: "42", type: number }
    #|      A3: { value: "#N/A", type: error }
    #|
  let reopened = @xlsx.read(@cli.compile(source, file="spec.yaml")[:])
  // `type: text` on a number stores a string cell; `type: number` on a string
  // stores a numeric cell.
  assert_true(reopened.get_cell_value_raw("S", "A1") is Some(String("42")))
  assert_true(reopened.get_cell_value_raw("S", "A2") is Some(Numeric(42.0)))
  assert_eq(reopened.get_cell_value("S", "A3", raw=true), Some("#N/A"))
}

///|
/// Golden round-trip for a *split* spec: the data lives in one file and the
/// formatting in another, and they compile to the one workbook (ADR-005).
test "golden: an included data file compiles into the same workbook" {
  let source =
    #|defs:
    #|  styles:
    #|    $include: theme.yaml
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      $include: data.yaml
    #|
  let files = {
    "theme.yaml": "header: { font: { bold: true } }\n",
    "data.yaml": "A1: { value: Region, style: header }\nB1: 2400000\n",
  }
  let bytes = @cli.compile(source, file="spec.yaml", resolve=(_from, path) => {
    match files.get(path) {
      Some(text) => { name: path, source: text }
      None => raise @diag.SchemaError(@diag.Diagnostic::new("missing \{path}"))
    }
  })
  let reopened = @xlsx.read(bytes[:])
  assert_eq(reopened.get_cell("S", "A1"), Some("Region"))
  assert_eq(reopened.get_cell("S", "B1"), Some("2400000"))
  // The style came from the other file and really applied.
  let style = reopened.get_cell_style("S", "A1")
  assert_true(style is Some(_) && style != Some(0))
  assert_eq(reopened.get_style(style.unwrap()).font.unwrap().bold, Some(true))
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
    Some(
      "spec.yaml: unknown top-level key 'title' (expected 'sheets', 'active', 'params', 'date1904', 'default_font', 'defs', 'properties', 'calc', or 'protect')",
    ),
  )
}

///|
test "extract surfaces what the backend could not read, not the error's name" {
  // `error_message` knew four of the six subdomain errors, so a failed
  // `yxl extract` printed `t-ujiie-g/yxl/diag.ReadError.ReadError` and nothing
  // else — a reader who hit one had to bisect the package part by part to find
  // out what was wrong with it (#55).
  let caught = try {
    @cli.extract(b"this is not a workbook", file="report.xlsx") |> ignore
    None
  } catch {
    err => Some(@cli.error_message(err))
  }
  guard caught is Some(message) else { fail("expected a ReadError") }
  assert_false(message.contains("diag.ReadError"))
  assert_true(message.contains("unreadable ZIP package"))
}

///|
test "directory_of names the directory a path sits in, on either platform" {
  // The executable makes this directory before writing a file an extracted spec
  // names, so it has to answer for the paths `resolve_path` produces — including
  // the mixed separators a Windows spec ends up with.
  assert_eq(@cli.directory_of("specs/report.yaml"), Some("specs/"))
  assert_eq(@cli.directory_of("specs\\report.yaml"), Some("specs\\"))
  assert_eq(@cli.directory_of("a/b/data/sales.csv"), Some("a/b/data/"))
  // The later separator wins, whichever kind it is.
  assert_eq(@cli.directory_of("specs\\data/sales.csv"), Some("specs\\data/"))
  assert_eq(@cli.directory_of("specs/data\\sales.csv"), Some("specs/data\\"))
  // A file with no directory part has none to make.
  assert_eq(@cli.directory_of("report.yaml"), None)
  assert_eq(@cli.directory_of(""), None)
  // A trailing separator is already a directory.
  assert_eq(@cli.directory_of("specs/"), Some("specs/"))
}

///|
test "resolve_path takes a path as relative to the file that wrote it" {
  // The ordinary case, either separator.
  assert_eq(
    @cli.resolve_path("specs/report.yaml", "data/q3.yaml"),
    "specs/data/q3.yaml",
  )
  assert_eq(
    @cli.resolve_path("specs\\report.yaml", "data/q3.yaml"),
    "specs\\data/q3.yaml",
  )
  // Nested, and back up a level — yxl passes `..` through for the OS to resolve.
  assert_eq(
    @cli.resolve_path("a/b/c.yaml", "../shared/theme.yaml"),
    "a/b/../shared/theme.yaml",
  )
  // No directory part: the path stands alone.
  assert_eq(@cli.resolve_path("report.yaml", "data/q3.yaml"), "data/q3.yaml")
}

///|
test "resolve_path leaves absolute paths alone, in every spelling" {
  for
    absolute in [
      "/etc/yxl/theme.yaml", // POSIX
       "C:\\specs\\theme.yaml", // Windows drive, backslash
       "c:/specs/theme.yaml", // Windows drive, forward slash, lowercase
       "\\\\server\\share\\theme.yaml", // UNC
    ] {
    assert_eq(@cli.resolve_path("specs/report.yaml", absolute), absolute)
  }
  // `C:x` is relative to that drive's own working directory, which yxl cannot
  // honour, so it is treated as relative rather than silently mis-resolved.
  assert_eq(
    @cli.resolve_path("specs/report.yaml", "C:theme.yaml"),
    "specs/C:theme.yaml",
  )
}

///|
test "resolve_path splits by character, so Japanese paths survive" {
  // On Japanese Windows a backslash *displays* as ¥ — the same character, so
  // this is the ordinary case wearing a different glyph.
  assert_eq(
    @cli.resolve_path("仕様\\報告書.yaml", "データ/売上.csv"),
    "仕様\\データ/売上.csv",
  )
  // CP932 encodes 表, ソ and 十 with 0x5C as their *second* byte. Splitting by
  // byte would cut these names in half; splitting by character cannot.
  for name in ["表", "ソ", "十", "貼", "能"] {
    assert_eq(
      @cli.resolve_path("\{name}/report.yaml", "theme.yaml"),
      "\{name}/theme.yaml",
    )
    // The same character as the *last* thing before the separator, which is
    // where a byte-wise split would do its damage.
    assert_eq(
      @cli.resolve_path("specs/一覧\{name}/report.yaml", "theme.yaml"),
      "specs/一覧\{name}/theme.yaml",
    )
  }
  // A genuine yen sign is a filename character, not a separator: this name must
  // survive whole, or an include beside it would resolve into nowhere.
  assert_eq(
    @cli.resolve_path("specs/見積¥1000.yaml", "theme.yaml"),
    "specs/theme.yaml",
  )
  assert_eq(@cli.resolve_path("見積¥1000.yaml", "theme.yaml"), "theme.yaml")
}
