// Resolving one path against another — the rule `$include` and `data:` follow,
// where a path written inside a spec is relative to the spec that wrote it.
//
// This is string work, not I/O, so it lives here rather than in the executable:
// the rules below are worth testing on every platform, and these tests run on
// all of them (ADR-003 keeps the actual reading in `cmd/main`).
//
// Both separators are accepted everywhere. Windows takes either, and a spec is
// portable text — the same `$include: data/x.yaml` should work whichever machine
// compiles it, whichever way the *outer* path was typed.

///|
/// Whether `path` stands on its own rather than hanging off another. Covers
/// POSIX (`/etc/x`), Windows drive paths (`C:\x`, `C:/x`), and UNC shares
/// (`\\server\share`).
fn is_absolute(path : String) -> Bool {
  // A drive letter is one ASCII letter, a colon, then a separator: `C:\x`. A
  // bare `C:x` is relative to that drive's current directory — a distinction
  // yxl has no way to honour, so it is treated as relative here too. Only the
  // first three characters decide either case, so only those are taken.
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
/// The two characters that separate path components.
///
/// A note for Japanese Windows, where the backslash *displays* as `¥`: that is
/// the same character (U+005C) in a font that draws it differently, so handling
/// `\` handles it. A genuine yen sign (U+00A5 `¥`, or U+FFE5 `￥`) is **not** a
/// separator — Windows itself treats it as an ordinary filename character, and
/// splitting on it here would break a perfectly legal name like `見積¥1000.yaml`
/// while rescuing nothing, since a path really containing one would fail to open
/// long before its directory mattered.
///
/// What does matter on those machines is that this splitting is by *character*,
/// never by byte: in CP932 the second byte of 表, ソ, 十 and friends is 0x5C, and
/// a byte-wise split would cut a filename in half. MoonBit strings are sequences
/// of characters, so that hazard does not arise — and a Windows CI job compiles
/// a spec under such a directory to keep it that way.
fn is_separator(ch : Char) -> Bool {
  ch == '/' || ch == '\\'
}

///|
/// Resolve `path`, as written inside the file `from`, against `from`'s
/// directory: an include in `specs/report.yaml` naming `data/q3.yaml` means
/// `specs/data/q3.yaml`. An absolute `path` is returned as it stands, and a
/// `from` with no directory part leaves `path` alone.
///
/// The separator already in `from` is kept, so the result reads like the path
/// the author typed; Windows accepts either, and mixing them is harmless.
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
/// Everything up to and including the last separator in `from` — the later of
/// the two characters `is_separator` names — or `None` when it names a file
/// with no directory part.
///
/// Public because the executable needs it too: a file an extracted spec names
/// goes in a directory that may not exist yet, and making it is the one thing
/// that has to happen before writing (ADR-003 keeps the writing out there).
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
