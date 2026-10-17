///|
/// What a `type:` reads a value as, on a cell or a layout column
/// (`docs/spec.md` §3, §25).
priv enum ValueType {
  Text
  Number
  Bool
  Date
  Duration
  Error
}

///|
/// A `type:` name. A layout column refuses `error` (`errors=false`): no export
/// sends one.
fn parse_value_type(
  name : String,
  file~ : String,
  context~ : String,
  errors~ : Bool,
) -> ValueType raise @diag.SchemaError {
  match name {
    "text" => Text
    "number" => Number
    "bool" => Bool
    "date" => Date
    "duration" => Duration
    "error" if errors => Error
    other => {
      let expected = if errors {
        "'text', 'number', 'bool', 'date', 'duration', or 'error'"
      } else {
        "'text', 'number', 'bool', 'date', or 'duration'"
      }
      raise schema_error(
        file~,
        "unknown type '\{other}' for \{context} (expected \{expected})",
      )
    }
  }
}

///|
/// `value` read as this type; `place` names it in a diagnostic.
fn ValueType::read(
  self : ValueType,
  value : @model.CellValue,
  file~ : String,
  place~ : String,
) -> @model.CellValue raise @diag.SchemaError {
  match (self, value) {
    (Text, Text(_)) | (Number, Number(_)) | (Bool, Bool(_)) => value
    (Text, Number(number)) => Text(number.to_string())
    (Text, Bool(flag)) => Text(bool_text(flag))
    (Number, Text(text)) =>
      Number(
        @string.parse_double(text) catch {
          _ => raise schema_error(file~, "\{place} is not a number: '\{text}'")
        },
      )
    (Bool, Text("true")) => Bool(true)
    (Bool, Text("false")) => Bool(false)
    (Bool, Text(text)) =>
      raise schema_error(
        file~,
        "\{place} is not a boolean (true or false): '\{text}'",
      )
    (Date, Text(text)) =>
      match @units.DateTime::parse(text) {
        Some(datetime) => Date(datetime)
        None =>
          raise schema_error(file~, "\{place} is not a valid date: '\{text}'")
      }
    (Duration, Text(text)) =>
      match @units.Duration::parse(text) {
        Some(duration) => Number(duration.to_serial())
        None =>
          raise schema_error(
            file~,
            "\{place} is not a valid duration: '\{text}' (expected H:MM or H:MM:SS, hours unbounded)",
          )
      }
    (Error, Text(text)) => {
      guard excel_errors.contains(text) else {
        raise schema_error(
          file~,
          "\{place} is not a valid Excel error literal: '\{text}'",
        )
      }
      Error(text)
    }
    _ =>
      raise schema_error(
        file~,
        "\{place} cannot be read as \{self.noun()}: '\{shown(value)}'",
      )
  }
}

///|
fn ValueType::noun(self : ValueType) -> String {
  match self {
    Text => "text"
    Number => "a number"
    Bool => "a boolean"
    Date => "a date"
    Duration => "a duration"
    Error => "an error"
  }
}

///|
/// The number format a value read as this type wears when nothing else sets
/// one, so a date or an elapsed time displays as one.
fn ValueType::default_format(
  self : ValueType,
  value : @model.CellValue,
) -> String? {
  match (self, value) {
    (Date, Date(datetime)) =>
      Some(
        if datetime.has_time() {
          DEFAULT_DATETIME_FORMAT
        } else {
          DEFAULT_DATE_FORMAT
        },
      )
    (Duration, Number(_)) => Some(DEFAULT_DURATION_FORMAT)
    _ => None
  }
}

///|
fn bool_text(flag : Bool) -> String {
  if flag {
    "true"
  } else {
    "false"
  }
}

///|
fn shown(value : @model.CellValue) -> String {
  match value {
    Text(text) => text
    Number(number) => number.to_string()
    Bool(flag) => bool_text(flag)
    _ => ""
  }
}

///|
/// ISO order, so what Excel shows matches what the spec wrote.
const DEFAULT_DATE_FORMAT : String = "yyyy-mm-dd"

///|
const DEFAULT_DATETIME_FORMAT : String = "yyyy-mm-dd hh:mm:ss"

///|
/// `[h]` keeps counting past 24 instead of rolling into days, which makes the
/// display an elapsed time rather than a time of day.
const DEFAULT_DURATION_FORMAT : String = "[h]:mm:ss"

///|
/// The Excel error literals a `type: error` value may hold.
let excel_errors : Array[String] = [
  "#DIV/0!", "#N/A", "#NAME?", "#NULL!", "#NUM!", "#REF!", "#VALUE!", "#SPILL!",
  "#CALC!", "#GETTING_DATA",
]
