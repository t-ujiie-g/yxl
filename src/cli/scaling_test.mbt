///|
/// The small end of the comparison. The same size the benchmark reports, so its
/// recorded figures describe this run too.
let scaling_base_rows : Int = bench_rows

///|
/// How much larger the second spec is. Wide enough that a quadratic term shows
/// through the linear work around it (see `max_scaling_ratio`), narrow enough
/// that the whole check is under a second.
let scaling_factor : Int = 16

///|
/// The ratio above which the curve is no longer linear enough to pass.
///
/// Linear is `scaling_factor` (16), and that is what a healthy pipeline measures
/// — 15.8 and 16.2 across runs. A loader made quadratic measures 42.6. This sits
/// between them, far enough above the first to survive a noisy shared runner and
/// far enough below the second to fail on it. It is a ceiling on the *shape*,
/// not a performance target: tightening it towards 16 would buy precision the
/// measurement cannot support, and would start failing on runner noise instead
/// of on regressions.
let max_scaling_ratio : Double = 26.0

///|
/// How many times each size is compiled. Only the fastest run counts: noise on a
/// shared machine can only ever *add* time, so the minimum is the closest thing
/// to the cost without it, and taking it is what makes a single unlucky sample
/// harmless rather than a failed build.
let scaling_runs : Int = 3

///|
test "compile cost stays linear in the size of the spec" {
  let small = bench_spec(scaling_base_rows)
  let large = bench_spec(scaling_base_rows * scaling_factor)
  // The small spec runs first and so absorbs the warm-up — the allocator
  // growing, the pages being faulted in. That biases the ratio *downwards*,
  // which is the safe direction for a ceiling.
  let small_us = fastest_compile(small)
  let large_us = fastest_compile(large)
  let ratio = large_us / small_us
  println(
    "scaling: \{scaling_base_rows} rows \{format_ms(small_us)} -> \{scaling_base_rows * scaling_factor} rows \{format_ms(large_us)}, ratio \{two_decimals(ratio)} for a \{scaling_factor}x (linear is \{scaling_factor}, ceiling \{two_decimals(max_scaling_ratio)})",
  )
  assert_true(ratio <= max_scaling_ratio)
}

///|
/// The shortest of `scaling_runs` compiles of `source`, in microseconds.
fn fastest_compile(source : String) -> Double {
  let mut best = compile_microseconds(source)
  for _ in 1..<scaling_runs {
    let elapsed = compile_microseconds(source)
    if elapsed < best {
      best = elapsed
    }
  }
  best
}

///|
/// One compile of `source`, in microseconds. The bytes are checked rather than
/// discarded so that neither the call nor the work behind it can be optimized
/// away as unused — a timing loop measuring nothing would pass forever.
fn compile_microseconds(source : String) -> Double {
  let start = @bench.monotonic_clock_start()
  let bytes = @cli.compile(source, file="bench.yaml") catch {
    e => abort("the scaling spec failed to compile: \{@cli.error_message(e)}")
  }
  let elapsed = @bench.monotonic_clock_end(start)
  guard bytes.length() > 0 else {
    abort("the scaling spec compiled to nothing")
  }
  elapsed
}

///|
/// Microseconds as milliseconds — the unit the benchmark reports in, so the two
/// can be read side by side.
fn format_ms(microseconds : Double) -> String {
  "\{two_decimals(microseconds / 1000.0)} ms"
}

///|
/// A non-negative `Double` to two decimal places. `Double`'s own rendering
/// spends seventeen digits saying what two say here, which buries the figure
/// the line exists to show.
fn two_decimals(value : Double) -> String {
  let hundredths = (value * 100.0).round().to_int()
  let fraction = (hundredths % 100).to_string().pad_start(2, '0')
  "\{hundredths / 100}.\{fraction}"
}
