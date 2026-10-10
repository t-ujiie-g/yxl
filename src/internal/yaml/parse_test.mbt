///|
test "parse classifies scalars: bare number vs quoted string vs bool" {
  let node = @yaml.parse("a: 1\nb: \"1\"\nc: hello\nd: true\n", file="t.yaml")
  @debug.debug_inspect(
    node,
    content=(
      #|Map(
      #|  [
      #|    ("a", Int(1)),
      #|    ("b", Str("1")),
      #|    ("c", Str("hello")),
      #|    ("d", Bool(true)),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse handles nested sequences and mappings" {
  let node = @yaml.parse("rows:\n  - [1, 2]\n  - k: 3.5\n", file="t.yaml")
  @debug.debug_inspect(
    node,
    content=(
      #|Map([("rows", Seq([Seq([Int(1), Int(2)]), Map([("k", Float(3.5))])]))])
    ),
  )
}

///|
test "the control-character escapes the library mis-decodes come back right" {
  // The parser library's escape table writes each code point's decimal value as
  // a hex literal, so `\r` used to decode to U+0013 (DC3) — a character XML
  // cannot carry, which made the workbook Excel opened a broken one (#45).
  let node = @yaml.parse(
    "a: \"x\\ry\"\nb: \"x\\vy\"\nc: \"x\\fy\"\n",
    file="t.yaml",
  )
  @debug.debug_inspect(
    node,
    content=(
      #|Map([("a", Str("x\ry")), ("b", Str("x\u{0b}y")), ("c", Str("x\u{0c}y"))])
    ),
  )
}

///|
test "the escapes the library gets right are left alone" {
  let node = @yaml.parse(
    "a: \"x\\ny\"\nb: \"x\\ty\"\nc: \"2'\"\n",
    file="t.yaml",
  )
  @debug.debug_inspect(
    node,
    content=(
      #|Map([("a", Str("x\ny")), ("b", Str("x\ty")), ("c", Str("2'"))])
    ),
  )
}

///|
test "parse treats an empty source as the null document" {
  assert_eq(@yaml.parse("", file="t.yaml"), @yaml.Null)
}

///|
test "parse reports malformed YAML as a YamlError naming the file" {
  let caught = try {
    @yaml.parse("a: [1, 2\n", file="broken.yaml") |> ignore
    None
  } catch {
    @diag.YamlError(d) => Some(d.render())
  }
  match caught {
    Some(message) => assert_true(message.contains("broken.yaml"))
    None => fail("expected a YamlError")
  }
}
