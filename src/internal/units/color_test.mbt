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

///|
test "argb and rgb render the two widths Excel's schemas ask for" {
  let plain = @units.Color::parse("1F77B4").unwrap()
  let translucent = @units.Color::parse("801F77B4").unwrap()
  // SpreadsheetML wants four bytes; a colour with no alpha of its own is plain.
  assert_eq(plain.argb(), "FF1F77B4")
  assert_eq(translucent.argb(), "801F77B4")
  // DrawingML wants three, and an alpha byte is dropped rather than kept.
  assert_eq(plain.rgb(), "1F77B4")
  assert_eq(translucent.rgb(), "1F77B4")
}
