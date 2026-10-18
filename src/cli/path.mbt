///|
/// Whether `path` stands on its own rather than hanging off another. Covers
/// POSIX (`/etc/x`), Windows drive paths (`C:\x`, `C:/x`), and UNC shares
/// (`\\server\share`).
fn is_absolute(path : String) -> Bool {
  // A drive letter, a colon, then a separator: `C:\x`. A bare `C:x` is relative
  // to that drive's current directory, which yxl cannot honour, so it counts as
  // relative.
  match path.iter().take(3).to_array() {
    [first, ..] if is_separator(first) => true
    [drive, ':', third] => is_drive_letter(drive) && is_separator(third)
    _ => false
  }
}

///|
fn is_drive_letter(ch : Char) -> Bool {
  (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')
}

///|
/// The two path separators. A yen sign is not one (Windows treats it as a name
/// character); `¥` displayed on Japanese Windows is `\` in a different font.
fn is_separator(ch : Char) -> Bool {
  ch == '/' || ch == '\\'
}

///|
/// Resolve `path`, as written inside `from`, against `from`'s directory. An
/// absolute `path`, or a `from` with no directory, leaves `path` as it is.
pub fn resolve_path(from : String, path : String) -> String {
  if is_absolute(path) {
    return path
  }
  match directory_of(from) {
    Some(directory) => directory + path
    None => path
  }
}

///|
/// `from` up to and including its last separator, or `None` when it has no
/// directory part.
pub fn directory_of(from : String) -> String? {
  let cut = match (from.rev_find("/"), from.rev_find("\\")) {
    (Some(slash), Some(backslash)) =>
      if slash > backslash {
        slash
      } else {
        backslash
      }
    (Some(slash), None) => slash
    (None, Some(backslash)) => backslash
    (None, None) => return None
  }
  Some(from[:cut + 1].to_owned())
}

///|
/// The workbook a spec builds to when nothing names another: `report.yxl.yaml`
/// -> `report.xlsx`. A name carrying none of the spellings yxl uses for a spec
/// keeps what it has and gains `.xlsx`.
fn workbook_name(spec : String) -> String {
  for suffix in [..spec_suffixes, ".yaml", ".yml"] {
    if spec.has_suffix(suffix) {
      return spec[:spec.length() - suffix.length()].to_owned() + ".xlsx"
    }
  }
  spec + ".xlsx"
}

///|
/// The endings that mark a file as a yxl spec.
let spec_suffixes : Array[String] = [".yxl.yaml", ".yxl.yml"]
