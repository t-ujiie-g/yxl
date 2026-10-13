///|
/// Where a recovered `data:` table is written, relative to the spec.
let data_directory : String = "data"

///|
/// Where a recovered picture is written, relative to the spec.
let asset_directory : String = "assets"

///|
/// The companion file names handed out so far.
priv struct Names {
  taken : @set.Set[String]
}

///|
fn Names::Names() -> Names {
  { taken: Set([]), }
}

///|
/// A free path under `directory` from `stem` and `extension`, claimed as it is
/// returned; a taken name gains a number (`sales_2.csv`).
fn Names::claim(
  self : Names,
  directory : String,
  stem : String,
  extension : String,
) -> String {
  let base = if stem.is_empty() { FALLBACK_STEM } else { stem }
  let mut path = "\{directory}/\{base}.\{extension}"
  let mut suffix = 2
  while self.taken.contains(path) {
    path = "\{directory}/\{base}_\{suffix}.\{extension}"
    suffix += 1
  }
  self.taken.add(path)
  path
}

///|
/// What a name is built from when the sheet's own name flattens to nothing —
/// a sheet called `???` still needs a file.
const FALLBACK_STEM : String = "sheet"

///|
/// A sheet's name as part of a file name: lower case, with spaces and punctuation
/// as `_`. Letters of any script pass through, so `売上` stays legible.
fn file_stem(sheet_name : String) -> String {
  let out = StringBuilder()
  for ch in sheet_name {
    if ch is ('a'..<='z' | '0'..<='9') {
      out.write_char(ch)
    } else if ch is ('A'..<='Z') {
      out.write_char(ch.to_ascii_lowercase())
    } else if ch is ('\u{00}'..<='\u{7f}') ||
      ch.is_whitespace() ||
      ch.is_control() {
      // The rest of ASCII is the punctuation the flattening exists for; past
      // ASCII only whitespace (U+3000, say) needs the same treatment.
      out.write_char('_')
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}
