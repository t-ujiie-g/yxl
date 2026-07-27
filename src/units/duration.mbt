///|
/// An elapsed time — `26:30:00` is twenty-six and a half hours, *not* a time
/// of day, so the hours may exceed 23. Excel stores it as a fraction of a day
/// under an elapsed format like `[h]:mm:ss`; `to_serial` renders that
/// fraction. Kept as components so what the spec wrote stays inspectable.
pub(all) struct Duration {
  hours : Int
  minutes : Int
  seconds : Int
} derive(Eq, Debug)

///|
/// Parse `H:MM` or `H:MM:SS` — hours unbounded, minutes and seconds 0–59.
/// Returns `None` for anything else; the caller turns `None` into a
/// diagnostic. A negative duration has no representation (Excel's 1900 date
/// system cannot display one), so `-` is simply not part of the syntax.
pub fn Duration::parse(text : String) -> Duration? {
  let parts = text.split(":").collect()
  guard parts.length() == 2 || parts.length() == 3 else { return None }
  let hours = parse_uint(parts[0])
  let minutes = parse_uint(parts[1])
  let seconds = if parts.length() == 3 { parse_uint(parts[2]) } else { Some(0) }
  guard hours is Some(hours) &&
    minutes is Some(minutes) &&
    seconds is Some(seconds) else {
    return None
  }
  guard minutes <= 59 && seconds <= 59 else { return None }
  Some({ hours, minutes, seconds })
}

///|
/// The Excel serial for this duration: its length as a fraction of a day.
/// Unlike a date's serial, it does not depend on the workbook's date system.
pub fn Duration::to_serial(self : Duration) -> Double {
  let seconds = self.hours * 3600 + self.minutes * 60 + self.seconds
  seconds.to_double() / 86400.0
}
