///|
test "DateTime::to_serial matches known Excel 1900-system values" {
  let serial = (y, m, d) => {
    @units.DateTime::{
      year: y,
      month: m,
      day: d,
      hour: 0,
      minute: 0,
      second: 0,
    }.to_serial(Date1900)
  }
  assert_eq(serial(1900, 1, 1), 1.0)
  assert_eq(serial(1900, 2, 28), 59.0)
  // The 1900 leap-year bug skips the phantom serial 60 (1900-02-29).
  assert_eq(serial(1900, 3, 1), 61.0)
  assert_eq(serial(2000, 1, 1), 36526.0)
}

///|
test "DateTime::to_serial handles the 1904 system and time fractions" {
  let midnight = (y, m, d) => @units.DateTime::{
    year: y,
    month: m,
    day: d,
    hour: 0,
    minute: 0,
    second: 0,
  }
  assert_eq(midnight(1904, 1, 1).to_serial(Date1904), 0.0)
  assert_eq(midnight(1904, 1, 2).to_serial(Date1904), 1.0)
  // The 1904 epoch is 1462 days behind the 1900 epoch.
  assert_eq(midnight(2000, 1, 1).to_serial(Date1904), 36526.0 - 1462.0)
  // Time of day is a fraction of a day.
  assert_eq(
    @units.DateTime::{
      year: 1900,
      month: 1,
      day: 1,
      hour: 12,
      minute: 0,
      second: 0,
    }.to_serial(Date1900),
    1.5,
  )
}

///|
test "DateTime::parse reads dates and date-times" {
  assert_eq(
    @units.DateTime::parse("2026-07-23"),
    Some(@units.DateTime::{
      year: 2026,
      month: 7,
      day: 23,
      hour: 0,
      minute: 0,
      second: 0,
    }),
  )
  guard! @units.DateTime::parse("2026-07-23") is Some(date)
  assert_false(date.has_time())
  assert_eq(
    @units.DateTime::parse("2026-07-23 14:30:05"),
    Some(@units.DateTime::{
      year: 2026,
      month: 7,
      day: 23,
      hour: 14,
      minute: 30,
      second: 5,
    }),
  )
  // 'T' separator and an omitted seconds field are both accepted.
  guard! @units.DateTime::parse("2026-07-23T14:30") is Some(datetime)
  assert_true(datetime.has_time())
  assert_eq(datetime.second, 0)
  // A leap day in a real leap year is valid.
  assert_eq(
    @units.DateTime::parse("2024-02-29"),
    Some(@units.DateTime::{
      year: 2024,
      month: 2,
      day: 29,
      hour: 0,
      minute: 0,
      second: 0,
    }),
  )
}

///|
test "DateTime::parse rejects malformed and impossible dates" {
  for
    bad in [
      "", "hello", "2026-07", "2026/07/23", "2026-13-01", "2026-00-01", "2026-02-30",
      "2023-02-29", "1900-02-29", "2026-07-23 25:00", "2026-07-23 12:60", "2026-07-23 12:00:99",
    ] {
    assert_eq(@units.DateTime::parse(bad), None)
  }
}
