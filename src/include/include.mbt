///|
/// What an `$include` resolved to: the document's source text, and `name`, the
/// path the resolver actually opened. Diagnostics and nested relative includes
/// both use that name.
pub(all) struct Included {
  name : String
  source : String
}

///|
/// Given the file containing an `$include` and the path written in it, return
/// the included document. Raise when the file cannot be found or read.
pub type IncludeResolver = (String, String) -> Included raise

///|
/// What a binary file (an image) resolved to: its bytes, and the path the
/// resolver actually opened.
pub(all) struct IncludedBytes {
  name : String
  data : Bytes
}

///|
/// `IncludeResolver` for files that are not text.
pub type BytesResolver = (String, String) -> IncludedBytes raise
