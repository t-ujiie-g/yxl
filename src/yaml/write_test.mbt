// Tests for the YAML writer. Two kinds: the *round trip* — every node comes
// back as itself through `parse` — which is what makes the writer trustworthy,
// and a handful of layout assertions, which are what make its output worth
// reading. The first would pass on a writer that emitted one long quoted line.

///|
/// Write a node and read it back, which must return the node unchanged.
fn round_trip(node : @yaml.Node) -> @yaml.Node raise {
  @yaml.parse(@yaml.write(node), file="written.yaml")
}

///|
/// Assert a node survives being written and read.
fn survives(node : @yaml.Node) -> Unit raise {
  assert_eq(round_trip(node), node)
}

///|
test "scalars come back as the type they went in as" {
  for
    node in [
      @yaml.Str("plain"),
      @yaml.Int(42),
      @yaml.Float(0.085),
      @yaml.Bool(true),
      @yaml.Bool(false),
      @yaml.Null,
    ] {
    survives(@yaml.Map([("a", node)]))
  }
}

///|
test "text that looks like another type survives as text" {
  // Each of these is read as something other than a string when written plain:
  // a number, a boolean, null, or nothing at all.
  for
    text in [
      "007", "42", "0.5", ".5", "1_000", "0x10", "+5", "-5", "1e3", "true", "True",
      "TRUE", "false", "False", "null", "NULL", "~", "-", "",
    ] {
    survives(@yaml.Map([("a", @yaml.Str(text))]))
  }
}

///|
test "text carrying YAML's own punctuation survives" {
  for
    text in [
      "#,##0", "a: b", "a # b", "- item", "[a]", "{a}", "&anchor", "*alias", "!tag",
      "|block", ">folded", "'quoted'", "\"quoted\"", "%directive", "@at", "`tick",
      "?question", "trailing ", " leading", "ends:", "x\ny", "tab\there", "back\\slash",
    ] {
    survives(@yaml.Map([("a", @yaml.Str(text))]))
  }
}

///|
test "control characters survive, including the ones YAML gives a letter" {
  // The parser's escape table decodes `\r` to U+13, `\v` to U+11, `\f` to
  // U+12, and `\e` to U+27 — decimal code points written as hex — so the
  // writer spells every control character but `\n` and `\t` as `\u00XX`,
  // which the parser does read right. A cell holding Windows line breaks is
  // the case that found this: `\r\n` written the friendly way came back as
  // a different string in every multi-line cell of a real workbook.
  for text in ["a\r\nb", "bell\u{07}", "vt\u{0b}", "ff\u{0c}", "esc\u{1b}"] {
    survives(@yaml.Map([("a", @yaml.Str(text))]))
  }
}

///|
test "a carriage return is written as its code point, not its letter" {
  assert_eq(
    @yaml.write(@yaml.Map([("a", @yaml.Str("x\r\ny"))])),
    "a: \"x\\u000d\\ny\"\n",
  )
}

///|
test "text that needs no quoting survives too" {
  for
    text in [
      "SUM(B2:B3)", "B2*C2", "APAC", "data/sales.csv", "$ref", "_private", "a#b",
      "Region name", "2026 report", "50%",
    ] {
    survives(@yaml.Map([("a", @yaml.Str(text))]))
  }
}

///|
test "a whole float keeps its fraction, so it does not read back as an integer" {
  // `Double`'s own rendering drops it: 1.0 prints as "1".
  assert_eq(@yaml.write(@yaml.Map([("a", @yaml.Float(1.0))])), "a: 1.0\n")
  survives(@yaml.Map([("a", @yaml.Float(1.0))]))
  survives(@yaml.Map([("a", @yaml.Float(-3.0))]))
  survives(@yaml.Map([("a", @yaml.Float(1.0e20))]))
  survives(@yaml.Map([("a", @yaml.Float(0.0))]))
}

///|
test "the infinities and NaN have spellings that survive" {
  assert_eq(
    round_trip(@yaml.Map([("a", @yaml.Float(@double.infinity))])),
    @yaml.Map([("a", @yaml.Float(@double.infinity))]),
  )
  assert_eq(
    round_trip(@yaml.Map([("a", @yaml.Float(@double.neg_infinity))])),
    @yaml.Map([("a", @yaml.Float(@double.neg_infinity))]),
  )
  // NaN is not equal to itself, so it is checked by shape.
  let read = round_trip(@yaml.Map([("a", @yaml.Float(@double.not_a_number))]))
  assert_true(read is Map([("a", Float(value))]) && value.is_nan())
}

///|
test "keys that look like other types survive as keys" {
  for key in ["007", "true", "null", "-", "a: b", "#hash", " leading"] {
    survives(@yaml.Map([(key, @yaml.Int(1))]))
  }
}

///|
test "an empty key is outside the seam's alphabet, in both directions" {
  // `write` is the inverse of `parse` for every node `parse` can produce, and an
  // empty key is not one of them: the parser refuses `"": 1` on the way in too
  // ("doesn't support non-string key"), so there is no such `Node` to write.
  // Recorded here so a parser swap (ADR-010) notices the limit lifting.
  let written = @yaml.write(@yaml.Map([("", @yaml.Int(1))]))
  assert_eq(written, "\"\": 1\n")
  let read = try {
    @yaml.parse(written, file="w") |> ignore
    None
  } catch {
    @diag.YamlError(d) => Some(d.render())
  }
  assert_true(read is Some(_))
}

///|
test "nesting survives to any depth the schema uses" {
  survives(
    @yaml.Map([
      (
        "sheets",
        @yaml.Seq([
          @yaml.Map([
            ("name", @yaml.Str("Sales")),
            (
              "cells",
              @yaml.Map([
                ("A1", @yaml.Str("Region")),
                ("B1", @yaml.Int(2400000)),
                (
                  "C1",
                  @yaml.Map([
                    ("formula", @yaml.Str("SUM(B1:B1)")),
                    ("style", @yaml.Str("header")),
                  ]),
                ),
              ]),
            ),
            (
              "formulas",
              @yaml.Seq([
                @yaml.Map([
                  ("at", @yaml.Str("D2:D9")),
                  ("formula", @yaml.Str("B2*C2")),
                ]),
              ]),
            ),
          ]),
        ]),
      ),
    ]),
  )
}

///|
test "empty collections survive, in the only form they have" {
  survives(@yaml.Map([("a", @yaml.Seq([])), ("b", @yaml.Map([]))]))
  assert_eq(@yaml.write(@yaml.Map([("a", @yaml.Seq([]))])), "a: []\n")
  assert_eq(@yaml.write(@yaml.Map([("a", @yaml.Map([]))])), "a: {}\n")
  // A whole document that is empty has nowhere to put a key.
  assert_eq(@yaml.write(@yaml.Map([])), "{}\n")
  assert_eq(@yaml.write(@yaml.Seq([])), "[]\n")
}

///|
test "a bare scalar document survives" {
  survives(@yaml.Str("just text"))
  survives(@yaml.Int(7))
  survives(@yaml.Null)
}

///|
test "a sequence of sequences survives" {
  survives(
    @yaml.Map([
      (
        "values",
        @yaml.Seq([
          @yaml.Seq([@yaml.Str("APAC"), @yaml.Int(2400000)]),
          @yaml.Seq([@yaml.Str("EMEA"), @yaml.Int(1750000)]),
        ]),
      ),
    ]),
  )
}

///|
test "the output is block style, indented two spaces, in the order given" {
  let written = @yaml.write(
    @yaml.Map([
      ("active", @yaml.Str("Sales")),
      (
        "sheets",
        @yaml.Seq([
          @yaml.Map([
            ("name", @yaml.Str("Sales")),
            ("cells", @yaml.Map([("A1", @yaml.Str("Region"))])),
          ]),
        ]),
      ),
    ]),
  )
  // Key order is the caller's; nothing is sorted, and nothing is inlined.
  inspect(
    written,
    content=(
      #|active: Sales
      #|sheets:
      #|  - name: Sales
      #|    cells:
      #|      A1: Region
      #|
    ),
  )
}

///|
test "quoting appears only where the syntax forces it" {
  inspect(
    @yaml.write(
      @yaml.Map([
        ("plain", @yaml.Str("APAC")),
        ("numeric", @yaml.Str("007")),
        ("format", @yaml.Str("#,##0")),
        ("formula", @yaml.Str("SUM(B2:B3)")),
      ]),
    ),
    content=(
      #|plain: APAC
      #|numeric: "007"
      #|format: "#,##0"
      #|formula: SUM(B2:B3)
      #|
    ),
  )
}
