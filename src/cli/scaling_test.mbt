// The guardrail the benchmark next door cannot be: a check that fails the build
// when compile cost stops being linear in spec size.
//
// A wall-clock threshold cannot do that job. A hosted runner is several times
// slower than a laptop and varies run to run, so any fixed number is either so
// tight it fails on a slow morning or so loose it catches nothing. A *ratio*
// measured in one job on one machine has no such problem: whatever slows the
// large spec slows the small one too, and the machine's speed cancels out.
//
// So what is asserted here is the shape of the curve rather than a point on it.
// Sixteen times the rows should cost about sixteen times as much, which is what
// the pipeline does today. The regression this catches is the one that actually
// matters — a scan nested inside the per-cell loop, turning the pipeline
// quadratic. A constant-factor slowdown moves the ratio not at all and is
// deliberately *not* caught here: `moon bench` measures that, and a human reads
// it.
//
// The band below is **calibrated against a real injected regression**, not
// guessed. Textbook reasoning says a quadratic pipeline costs `factor` squared,
// so any ceiling short of that will do; the pipeline is not a textbook, because
// its linear work still dominates at these sizes and dilutes the quadratic term.
// Measured on one machine, with a linear scan of the sheet's cells added to the
// per-cell loop: at a factor of 8 the ratio moved only 7.0 → 15.0, so the
// obvious ceiling of 20 would have let a genuinely quadratic loader through.
// Widening to 16 separates them properly — 16.0 clean against 42.6 with the
// scan — and the ceiling sits between the two, a little over 1.6× from each.

///|
/// The small end of the comparison. The same size the benchmark reports, so its
/// recorded figures describe this run too.
let scaling_base_rows : Int = bench_rows

///|
/// How much larger the second spec is. Wide enough that a quadratic term shows
/// through the linear work around it (see the calibration above), narrow enough
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
  // Printed whether or not it passes: a run that only says "ok" tells a reader
  // reviewing a performance change nothing, and this is the one place in the
  // suite where the number is the point.
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
