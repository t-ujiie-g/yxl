///|
test "a duration parses hours beyond a day, with or without seconds" {
  assert_eq(
    @units.Duration::parse("26:30:00"),
    Some(@units.Duration::{ hours: 26, minutes: 30, seconds: 0, }),
  )
  assert_eq(
    @units.Duration::parse("0:05"),
    Some(@units.Duration::{ hours: 0, minutes: 5, seconds: 0, }),
  )
  assert_eq(
    @units.Duration::parse("100:00:59"),
    Some(@units.Duration::{ hours: 100, minutes: 0, seconds: 59, }),
  )
}

///|
test "a malformed duration is None" {
  for
    bad in [
      "", "26", "26:", ":30", "26:60:00", "26:30:60", "-1:00", "26:30:00:00", "1.5:00",
      "26:30 ", "1:05pm",
    ] {
    assert_eq(@units.Duration::parse(bad), None)
  }
}

///|
test "a duration's serial is its fraction of a day" {
  assert_eq(@units.Duration::parse("36:00:00").unwrap().to_serial(), 1.5)
  assert_eq(@units.Duration::parse("6:00").unwrap().to_serial(), 0.25)
  assert_eq(@units.Duration::parse("0:00:00").unwrap().to_serial(), 0.0)
  // 26:30:00 = 95400 seconds of 86400 in a day.
  assert_eq(
    @units.Duration::parse("26:30:00").unwrap().to_serial(),
    95400.0 / 86400.0,
  )
}
