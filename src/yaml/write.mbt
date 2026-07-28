// The other direction across the parser seam: a `Node` back to YAML text.
// `parse` exists so the pipeline never depends on the backend parser; this
// exists because nothing in the toolchain writes YAML at all, and `yxl extract`
// (ADR-017) has to produce a spec somebody would keep. So readability is the
// requirement, not an afterthought: block style throughout, no more quoting than
// the syntax forces, and the key order the caller chose left alone.
//
// The rules below are pinned to what *our* parser does, verified against it
// rather than assumed from the YAML spec — it reads `yes` as text but `TRUE` as
// a boolean, `007` as the number 7, and a lone `-` not at all.

///|
/// Render a document as YAML text, ending in a newline.
///
/// Block style throughout: a mapping is `key: value` and a sequence is `- item`,
/// nested two spaces at a time, which is the shape `docs/spec.md` and the
/// `examples/` corpus are written in. An empty collection has no block form, so
/// it falls back to `{}` / `[]`.
///
/// Scalars are written plain wherever the syntax allows and double-quoted where
/// it does not — `007` and `TRUE` come back as the *text* they went in as, not
/// as a number and a boolean. `write` is therefore the inverse of `parse` for
/// every `Node` that `parse` can produce, which the round-trip tests assert
/// directly.
pub fn write(node : Node) -> String {
  let out = StringBuilder::new()
  match node {
    Map(entries) if !entries.is_empty() =>
      write_map(out, entries, indent=0, inline_first=false)
    Seq(items) if !items.is_empty() =>
      write_seq(out, items, indent=0, inline_first=false)
    // A document that is a bare scalar, or an empty collection, has nothing to
    // lay out; one line carries it.
    other => {
      out.write_string(scalar(other))
      out.write_char('\n')
    }
  }
  out.to_string()
}

///|
/// A mapping's entries, one `key: value` line each, at `indent` levels of two
/// spaces.
fn write_map(
  out : StringBuilder,
  entries : Array[(String, Node)],
  indent~ : Int,
  inline_first~ : Bool,
) -> Unit {
  for index, entry in entries {
    let (key, value) = entry
    // `inline_first` says the opening line is already positioned — by the `- `
    // of the sequence item this mapping belongs to. Every later line still has
    // to be indented to sit under it.
    if index > 0 || !inline_first {
      pad(out, indent)
    }
    out.write_string(quoted_key(key))
    out.write_char(':')
    write_value(out, value, indent~)
  }
}

///|
/// A sequence's items, one `- item` line each.
fn write_seq(
  out : StringBuilder,
  items : Array[Node],
  indent~ : Int,
  inline_first~ : Bool,
) -> Unit {
  for index, item in items {
    if index > 0 || !inline_first {
      pad(out, indent)
    }
    out.write_string("- ")
    match item {
      // A collection under a `-` opens on the same line and continues one level
      // in, which is where the `- ` already put it. Anything else would indent
      // the block twice for no gain in clarity.
      Map(entries) if !entries.is_empty() =>
        write_map(out, entries, indent=indent + 1, inline_first=true)
      Seq(nested) if !nested.is_empty() =>
        write_seq(out, nested, indent=indent + 1, inline_first=true)
      other => {
        out.write_string(scalar(other))
        out.write_char('\n')
      }
    }
  }
}

///|
/// What follows a `key:` — the value on the same line when it is a scalar, or a
/// block underneath when it is a collection.
fn write_value(out : StringBuilder, value : Node, indent~ : Int) -> Unit {
  match value {
    Map(entries) if !entries.is_empty() => {
      out.write_char('\n')
      write_map(out, entries, indent=indent + 1, inline_first=false)
    }
    Seq(items) if !items.is_empty() => {
      out.write_char('\n')
      write_seq(out, items, indent=indent + 1, inline_first=false)
    }
    other => {
      out.write_char(' ')
      out.write_string(scalar(other))
      out.write_char('\n')
    }
  }
}

///|
fn pad(out : StringBuilder, indent : Int) -> Unit {
  for _ in 0..<indent {
    out.write_string("  ")
  }
}

///|
/// One scalar, and the empty collections that have no block form.
fn scalar(node : Node) -> String {
  match node {
    Str(text) => quoted_if_needed(text)
    Int(number) => number.to_string()
    Float(number) => float_literal(number)
    Bool(flag) => if flag { "true" } else { "false" }
    Null => "null"
    Seq(_) => "[]"
    Map(_) => "{}"
  }
}

///|
/// A float that reads back as a float. `Double`'s own rendering drops the
/// fraction from a whole number — `1.0` prints as `1`, which would parse as an
/// *integer* and change the node's type — so a decimal point is added where the
/// text carries no sign of one. The infinities and NaN have their own YAML
/// spellings, which our parser reads.
fn float_literal(number : Double) -> String {
  if number.is_nan() {
    return ".nan"
  }
  if number.is_inf() {
    return if number > 0.0 { ".inf" } else { "-.inf" }
  }
  let text = number.to_string()
  let exponential = text.contains(".") ||
    text.contains("e") ||
    text.contains("E")
  if exponential {
    text
  } else {
    text + ".0"
  }
}

///|
/// A mapping key, quoted on the same rules as any other text. A key is read back
/// as a plain string whatever it looks like, but `007:` and `true:` would still
/// *parse* as a number and a boolean before being turned into one.
fn quoted_key(key : String) -> String {
  quoted_if_needed(key)
}

///|
/// Text as a YAML scalar: plain where the syntax allows it, double-quoted where
/// it does not.
fn quoted_if_needed(text : String) -> String {
  if needs_quoting(text) {
    quote(text)
  } else {
    text
  }
}

///|
/// Whether `text` would come back as something other than itself, or not parse
/// at all, if written plain.
///
/// The test is deliberately conservative at the *first* character: anything that
/// is not a letter, `_`, `$` or `/` gets quoted, which covers every YAML
/// indicator (`- ? : , [ ] { } # & * ! | > ' " % @` and the backtick) and every
/// way a number can start (a digit, `+`, `-`, `.`) in one rule rather than a
/// list to keep in step with the parser.
fn needs_quoting(text : String) -> Bool {
  guard !text.is_empty() else { return true }
  // `null`, `true` and `false` are read as their types in any case, and `~` is
  // another spelling of null.
  let lowered = text.to_lower()
  if lowered is ("null" | "true" | "false" | "~") {
    return true
  }
  guard text.iter().head() is Some(first) else { return true }
  guard is_plain_start(first) else { return true }
  let chars = text.iter().to_array()
  for index, ch in chars {
    // A control character has no plain representation.
    if ch.to_int() < 0x20 || ch.to_int() == 0x7F {
      return true
    }
    // `: ` starts a value and ` #` starts a comment; a trailing `:` reads as a
    // key with no value.
    if ch == ':' && (index + 1 == chars.length() || chars[index + 1] == ' ') {
      return true
    }
    if ch == '#' && index > 0 && chars[index - 1] == ' ' {
      return true
    }
  }
  // Trailing space is not preserved by a plain scalar. A leading one cannot
  // reach here — a space is not a plain start.
  chars[chars.length() - 1] == ' '
}

///|
/// Whether `ch` may open a plain scalar.
fn is_plain_start(ch : Char) -> Bool {
  ch is ('A'..='Z' | 'a'..='z') || ch is ('_' | '$' | '/')
}

///|
/// Text in double quotes, with the escapes YAML's double-quoted style defines.
/// Control characters go out as `\u00XX`, which is the only form that survives
/// a round trip.
fn quote(text : String) -> String {
  let out = StringBuilder::new()
  out.write_char('"')
  for ch in text {
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if ch.to_int() < 0x20 || ch.to_int() == 0x7F {
          out.write_string("\\u\{hex4(ch.to_int())}")
        } else {
          out.write_char(ch)
        }
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// A code point as exactly four lowercase hex digits.
fn hex4(code : Int) -> String {
  let digits = "0123456789abcdef".to_array()
  let out = StringBuilder::new()
  for shift in [12, 8, 4, 0] {
    out.write_char(
      digits[(code.reinterpret_as_uint() >> shift).reinterpret_as_int() & 0xF],
    )
  }
  out.to_string()
}
