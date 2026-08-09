///|
/// Rows in the generated spec. Five columns each, so `rows * 5` cells.
let bench_rows : Int = 400

///|
/// A spec of `rows` × 5 cells: two text columns, two numbers, and a formula
/// over the row — a shape close to a real sheet, and one that exercises the
/// shared-string table (the region names repeat) as well as the number path.
fn bench_spec(rows : Int) -> String {
  let regions = ["APAC", "EMEA", "AMER", "LATAM"]
  let out = StringBuilder::new()
  out.write_string("sheets:\n  - name: Sales\n    cells:\n")
  for row in 1..<=rows {
    let region = regions[row % regions.length()]
    out.write_string("      A\{row}: \{region}\n")
    out.write_string("      B\{row}: Product \{row}\n")
    out.write_string("      C\{row}: \{row * 1000}\n")
    out.write_string("      D\{row}: \{row % 97}\n")
    out.write_string("      E\{row}: { formula: \"C\{row}*D\{row}\" }\n")
  }
  out.to_string()
}

///|
test "bench compile whole pipeline n=400 rows" (it : @bench.T) {
  let source = bench_spec(bench_rows)
  it.bench(() => {
    it.keep(@cli.compile(source, file="bench.yaml")) catch {
      e =>
        abort("the benchmark spec failed to compile: \{@cli.error_message(e)}")
    }
  })
}

///|
test "bench compile parse only n=400 rows" (it : @bench.T) {
  let source = bench_spec(bench_rows)
  it.bench(() => {
    it.keep(@yaml.parse(source, file="bench.yaml")) catch {
      e => abort("the benchmark spec failed to parse: \{@cli.error_message(e)}")
    }
  })
}

///|
test "bench compile load only n=400 rows" (it : @bench.T) {
  let parsed = @yaml.parse(bench_spec(bench_rows), file="bench.yaml")
  it.bench(() => {
    it.keep(@loader.load(parsed, file="bench.yaml")) catch {
      e => abort("the benchmark spec failed to load: \{@cli.error_message(e)}")
    }
  })
}

///|
test "bench compile emit only n=400 rows" (it : @bench.T) {
  let workbook = @loader.load(
    @yaml.parse(bench_spec(bench_rows), file="bench.yaml"),
    file="bench.yaml",
  )
  it.bench(() => {
    it.keep(@emit.to_bytes(workbook)) catch {
      e =>
        abort("the benchmark workbook failed to emit: \{@cli.error_message(e)}")
    }
  })
}
