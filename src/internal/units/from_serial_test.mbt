///|
fn civil(year : Int, month : Int, day : Int) -> @units.DateTime {
  { year, month, day, hour: 0, minute: 0, second: 0, }
}

///|
test "a date survives the round trip through its serial, in both systems" {
  for system in [@units.Date1900, @units.Date1904] {
    for
      date in [
        civil(1900, 1, 1),
        civil(1900, 3, 1),
        civil(1904, 1, 1),
        civil(1970, 1, 1),
        civil(2000, 2, 29),
        civil(2026, 7, 28),
        civil(2100, 12, 31),
        { ..civil(2026, 7, 28), hour: 13, minute: 45, second: 30, },
        { ..civil(2026, 7, 28), hour: 23, minute: 59, second: 59, },
      ] {
      // The 1904 system has no dates before 1904.
      if system is Date1904 && date.year < 1904 {
        continue
      }
      assert_eq(
        (date, @units.DateTime::from_serial(date.to_serial(system), system)),
        (date, Some(date)),
      )
    }
  }
}

///|
test "known Excel serials name the dates Excel names" {
  assert_eq(
    @units.DateTime::from_serial(1.0, Date1900),
    Some(civil(1900, 1, 1)),
  )
  // Serial 61 is 1900-03-01: Excel counts a nonexistent 1900-02-29 at 60.
  assert_eq(
    @units.DateTime::from_serial(61.0, Date1900),
    Some(civil(1900, 3, 1)),
  )
  assert_eq(
    @units.DateTime::from_serial(45000.0, Date1900),
    Some(civil(2023, 3, 15)),
  )
  assert_eq(
    @units.DateTime::from_serial(0.0, Date1904),
    Some(civil(1904, 1, 1)),
  )
}

///|
test "a serial with no date behind it is None, not a wrong date" {
  // Excel's phantom 1900-02-29.
  assert_eq(@units.DateTime::from_serial(60.0, Date1900), None)
  assert_eq(@units.DateTime::from_serial(-1.0, Date1900), None)
  assert_eq(@units.DateTime::from_serial(1.0e300, Date1900), None)
}

///|
test "a fraction a hair under midnight rounds into the next day" {
  let almost = 45000.0 + 86399.6 / 86400.0
  assert_eq(
    @units.DateTime::from_serial(almost, Date1900),
    Some(civil(2023, 3, 16)),
  )
}
