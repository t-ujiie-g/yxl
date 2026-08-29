///|
/// Where a recovered `data:` table is written, relative to the spec.
let data_directory : String = "data"

///|
/// Where a recovered picture is written, relative to the spec.
let asset_directory : String = "assets"

///|
/// The names handed out so far, so a second file cannot take a first one's.
///
/// One of these per directory is enough — a table is a `data/…` and a picture an
/// `assets/…`, so the two kinds cannot collide with each other — but nothing
/// stops a caller sharing one across both if the directories ever converge.
priv struct Names {
  taken : @set.Set[String]
}

///|
fn Names::Names() -> Names {
  { taken: Set([]), }
}

///|
/// A free path under `directory`, built from `stem` and `extension`, and marked
/// as taken in the same breath — the recording is what makes the *next* call
/// correct, and leaving it to the caller is what let the two copies drift.
///
/// A name already given out gets a number before its extension: `sales.csv`,
/// then `sales_2.csv`.
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
/// A sheet's name as part of a file name: lower case, with whatever would make
/// the path need quoting on a command line turned into an underscore.
///
/// That is spaces and punctuation — a sheet may be called `Q3 Sales (final)` —
/// not scripts: a letter or digit passes through whatever alphabet it is from,
/// because a sheet called `売上` flattened to `__` names nothing, and beside a
/// second such sheet it is legible only by counting underscores.
fn file_stem(sheet_name : String) -> String {
  let out = StringBuilder()
  for ch in sheet_name {
    if ch is ('a'..='z' | '0'..='9') {
      out.write_char(ch)
    } else if ch is ('A'..='Z') {
      out.write_char(ch.to_ascii_lowercase())
    } else if ch is ('\u{00}'..='\u{7f}') ||
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
