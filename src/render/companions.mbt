// Naming the files an extracted spec is written beside.
//
// Two kinds go out — a `data:` table as CSV, a picture as its own bytes — and
// they are named the same way: a sheet's name flattened to something safe to
// type, numbered if it is already taken. The two used to carry a copy of that
// each, which is how the copies came to disagree about who records a name as
// taken and how an extension is removed to number one.
//
// Nothing here is recovered. A workbook keeps its pictures as numbered parts
// (`image1.png`) and remembers nothing at all about where a `data:` table came
// from, so every one of these names is invented.

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
  taken : Map[String, Unit]
}

///|
fn Names::new() -> Names {
  { taken: Map([]) }
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
  while self.taken.get(path) is Some(_) {
    path = "\{directory}/\{base}_\{suffix}.\{extension}"
    suffix += 1
  }
  self.taken[path] = ()
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
  let out = StringBuilder::new()
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
