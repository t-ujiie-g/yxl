///|
/// A calendar date, optionally with a time of day (all-zero time = a plain
/// date). Kept as civil components, not a serial number, so the model stays
/// independent of the workbook's date system; `to_serial` renders it.
pub(all) struct DateTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
} derive(Eq, Debug)

///|
/// Excel's two epochs. The 1900 system (the default) numbers 1900-01-01 as 1 and
/// carries Excel's historical bug of treating 1900 as a leap year; the 1904
/// system numbers 1904-01-01 as 0.
pub(all) enum DateSystem {
  Date1900
  Date1904
} derive(Eq, Debug)

///|
/// Whether a time of day is present (any of hour/minute/second is non-zero) —
/// the loader uses this to pick a date vs. date-time default format.
pub fn DateTime::has_time(self : DateTime) -> Bool {
  self.hour != 0 || self.minute != 0 || self.second != 0
}

///|
/// Parse `YYYY-MM-DD`, optionally followed by ` HH:MM[:SS]` or `THH:MM[:SS]`.
/// Returns `None` for anything malformed or for an impossible date (bad month,
/// or a day out of range for the month, including 1900-02-29). The caller turns
/// `None` into a diagnostic.
pub fn DateTime::parse(text : String) -> DateTime? {
  let (date_part, time_part) = split_once_either(text, ' ', 'T')
  let fields = date_part.to_owned().split("-").collect()
  guard fields.length() == 3 else { return None }
  let year = parse_uint(fields[0])
  let month = parse_uint(fields[1])
  let day = parse_uint(fields[2])
  guard year is Some(year) && month is Some(month) && day is Some(day) else {
    return None
  }
  guard month >= 1 && month <= 12 else { return None }
  guard day >= 1 && day <= days_in_month(year, month) else { return None }
  let (hour, minute, second) = match time_part {
    None => (0, 0, 0)
    Some(time) => {
      let parts = time.to_owned().split(":").collect()
      guard parts.length() == 2 || parts.length() == 3 else { return None }
      let hour = parse_uint(parts[0])
      let minute = parse_uint(parts[1])
      let second = if parts.length() == 3 {
        parse_uint(parts[2])
      } else {
        Some(0)
      }
      guard hour is Some(hour) &&
        minute is Some(minute) &&
        second is Some(second) else {
        return None
      }
      guard hour <= 23 && minute <= 59 && second <= 59 else { return None }
      (hour, minute, second)
    }
  }
  Some({ year, month, day, hour, minute, second, })
}

///|
/// The Excel serial number for this date/time under `system`: whole days since
/// the epoch plus the time as a fraction of a day.
pub fn DateTime::to_serial(self : DateTime, system : DateSystem) -> Double {
  let days = match system {
    Date1900 => {
      let raw = days_from_civil(self.year, self.month, self.day) -
        days_from_civil(1899, 12, 31)
      // The 1900 leap-year bug: Excel counts a nonexistent 1900-02-29, so every
      // date on or after 1900-03-01 is numbered one higher.
      if self.year > 1900 || (self.year == 1900 && self.month >= 3) {
        raw + 1
      } else {
        raw
      }
    }
    Date1904 =>
      days_from_civil(self.year, self.month, self.day) -
      days_from_civil(1904, 1, 1)
  }
  let seconds = self.hour * 3600 + self.minute * 60 + self.second
  days.to_double() + seconds.to_double() / 86400.0
}

///|
/// The date/time an Excel serial stands for under `system` — the inverse of
/// `to_serial`, for the direction `yxl extract` travels (ADR-017), where a file
/// holds serials and a spec wants dates.
///
/// A negative serial has no date to name, and neither does one so large that
/// the day count overflows; both give `None` rather than a wrong answer. The
/// time is rounded to the nearest second, because a serial is a fraction of a
/// day and the fraction rarely lands exactly on one.
pub fn DateTime::from_serial(serial : Double, system : DateSystem) -> DateTime? {
  guard serial >= 0.0 && serial < 3.0e6 && !serial.is_nan() else { return None }
  let whole = serial.floor()
  // Rounding first can carry into the next day, which is the right answer for a
  // serial a hair under midnight.
  let seconds = ((serial - whole) * 86400.0).round().to_int()
  let (days, seconds) = if seconds >= 86400 {
    (whole.to_int() + 1, seconds - 86400)
  } else {
    (whole.to_int(), seconds)
  }
  let epoch_days = match system {
    Date1900 => {
      let raw = days + days_from_civil(1899, 12, 31)
      // The 1900 leap-year bug in reverse: serial 60 is Excel's nonexistent
      // 1900-02-29, and everything after it is numbered one too high.
      if days >= 61 {
        raw - 1
      } else if days == 60 {
        return None
      } else {
        raw
      }
    }
    Date1904 => days + days_from_civil(1904, 1, 1)
  }
  let (year, month, day) = civil_from_days(epoch_days)
  Some({
    year,
    month,
    day,
    hour: seconds / 3600,
    minute: seconds % 3600 / 60,
    second: seconds % 60,
  })
}

///|
/// The civil date a day count stands for — the inverse of `days_from_civil`,
/// and the same algorithm run backwards.
fn civil_from_days(days : Int) -> (Int, Int, Int) {
  let days = days + 719468
  let era = (if days >= 0 { days } else { days - 146096 }) / 146097
  let day_of_era = days - era * 146097
  let year_of_era = (
      day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096
    ) /
    365
  let year = year_of_era + era * 400
  let day_of_year = day_of_era -
    (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  let month_prime = (5 * day_of_year + 2) / 153
  let day = day_of_year - (153 * month_prime + 2) / 5 + 1
  let month = if month_prime < 10 { month_prime + 3 } else { month_prime - 9 }
  (if month <= 2 { year + 1 } else { year }, month, day)
}

///|
/// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's
/// algorithm). Only *differences* are used here, so the choice of epoch cancels.
fn days_from_civil(year : Int, month : Int, day : Int) -> Int {
  let year = if month <= 2 { year - 1 } else { year }
  let era = (if year >= 0 { year } else { year - 399 }) / 400
  let year_of_era = year - era * 400
  let day_of_year = (153 * (if month > 2 { month - 3 } else { month + 9 }) + 2) /
    5 +
    day -
    1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  era * 146097 + day_of_era - 719468
}

///|
fn is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
/// Parse a non-empty run of ASCII digits into a non-negative integer; `None` for
/// empty or non-digit input. Shared by date parsing and the loader's row
/// selectors.
pub fn parse_uint(text : StringView) -> Int? {
  guard !text.is_empty() else { return None }
  let mut value = 0
  for ch in text {
    guard ch is ('0'..='9') else { return None }
    value = value * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
/// Split `text` on the first occurrence of either separator, returning the part
/// before it and the part after (the latter `None` if neither appears).
fn split_once_either(
  text : String,
  first : Char,
  second : Char,
) -> (StringView, StringView?) {
  match text.split_once(first.to_string()) {
    Some((before, after)) => (before, Some(after))
    None =>
      match text.split_once(second.to_string()) {
        Some((before, after)) => (before, Some(after))
        None => (text[:], None)
      }
  }
}
