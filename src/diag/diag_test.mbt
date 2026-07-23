///|
test "Pos::new stores 1-based line and column" {
  let p = @diag.Pos::new(3, 7)
  assert_eq(p.line, 3)
  assert_eq(p.col, 7)
}

///|
test "Span::point is zero-width (start == end)" {
  let span = @diag.Span::point("report.yxl.yaml", @diag.Pos::new(3, 7))
  assert_eq(span.start, span.end)
  assert_eq(span.render(), "report.yxl.yaml:3:7")
}

///|
test "Span::render shows the start position" {
  let span = @diag.Span::new(
    "a.yaml",
    @diag.Pos::new(10, 2),
    @diag.Pos::new(10, 9),
  )
  assert_eq(span.render(), "a.yaml:10:2")
}

///|
test "Diagnostic::render prefixes an anchored span" {
  let span = @diag.Span::point("sheet.yaml", @diag.Pos::new(4, 1))
  let d = @diag.Diagnostic::new("unknown key 'colour'", span~)
  assert_eq(d.render(), "sheet.yaml:4:1: unknown key 'colour'")
}

///|
test "Diagnostic::render omits the location when unanchored" {
  let d = @diag.Diagnostic::new("missing input file")
  assert_eq(d.span, None)
  assert_eq(d.render(), "missing input file")
}

///|
test "each subdomain error wraps its diagnostic and is distinguishable" {
  let span = @diag.Span::point("in.yaml", @diag.Pos::new(1, 1))
  let d = @diag.Diagnostic::new("bad yaml", span~)
  let yaml = @diag.YamlError(d)
  // Pattern-matching reaches the wrapped diagnostic...
  match yaml {
    YamlError(inner) => assert_eq(inner.render(), "in.yaml:1:1: bad yaml")
  }
  // ...and each stage's error is a distinct type.
  assert_true(@diag.SchemaError(d) is @diag.SchemaError(_))
  assert_true(@diag.ResolveError(d) is @diag.ResolveError(_))
  assert_true(@diag.EmitError(d) is @diag.EmitError(_))
  assert_true(@diag.CliError(d) is @diag.CliError(_))
}

///|
test "a raised subdomain error carries its span to the catch site" {
  fn parse() -> Unit raise @diag.SchemaError {
    raise @diag.SchemaError(
      @diag.Diagnostic::new(
        "expected a number",
        span=@diag.Span::point("x.yaml", @diag.Pos::new(2, 5)),
      ),
    )
  }

  let caught = try {
    parse()
    None
  } catch {
    SchemaError(d) => Some(d.render())
  }
  assert_eq(caught, Some("x.yaml:2:5: expected a number"))
}
