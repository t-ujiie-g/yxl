///|
test "Color::parse accepts 6- and 8-digit hex, canonicalizing to uppercase" {
  assert_eq(@units.Color::parse("ff0000").map(c => c.hex()), Some("FF0000"))
  assert_eq(@units.Color::parse("#00FF00").map(c => c.hex()), Some("00FF00"))
  assert_eq(@units.Color::parse("80ffffff").map(c => c.hex()), Some("80FFFFFF"))
}

///|
test "Color::parse rejects bad lengths and non-hex digits" {
  assert_eq(@units.Color::parse("FFF"), None)
  assert_eq(@units.Color::parse("1234567"), None)
  assert_eq(@units.Color::parse("GGGGGG"), None)
  assert_eq(@units.Color::parse(""), None)
}
