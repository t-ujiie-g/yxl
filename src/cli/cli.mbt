///|
/// Success.
pub let exit_ok : Int = 0

///|
/// A run-time failure: a bad spec (YAML/schema), an emit failure, or file I/O.
pub let exit_error : Int = 1

///|
/// A usage error: the command line itself was wrong.
pub let exit_usage : Int = 2

///|
/// The version this binary reports. Kept in step with `moon.mod`'s `version`;
/// CI fails the build if the two drift.
pub let version : String = "0.3.6"

///|
/// What the command line asked for. `params` carries the `--set name=value`
/// overrides. `Check` validates a spec and writes nothing, so — unlike `Build` —
/// it has no output path to carry.
pub(all) enum Command {
  Build(input~ : String, output~ : String, params~ : Map[String, String])
  Check(input~ : String, params~ : Map[String, String])
  /// Read a workbook and write the spec that would rebuild it (ADR-017).
  Extract(input~ : String, output~ : String, flat~ : Bool)
  /// Write `starter_spec` to a file someone can build straight away (#77).
  Init(output~ : String, force~ : Bool)
  Version
  Help
} derive(Eq, Debug)

///|
/// The spec `yxl init` writes: one empty sheet, not a worked example the reader
/// would have to delete first (#77). The build line names `output` itself, so
/// it is a command that works as it stands.
pub fn starter_spec(output~ : String) -> String {
  let workbook = workbook_name(output)
  (
    $|# A yxl spec: a workbook as text.
    $|# Build it with `yxl build \{output} -o \{workbook}`.
    $|# The format: docs/spec.md
    $|sheets:
    $|  - name: Sheet1
    $|
  )
}

///|
/// The full usage text, shown by `yxl help` and on a bare `yxl`.
pub let usage : String =
  #|yxl — compile a YAML workbook spec into a real .xlsx
  #|
  #|Usage:
  #|  yxl build <spec.yaml> -o <out.xlsx> [--set name=value]...
  #|  yxl build <spec.yaml> --check [--set name=value]...
  #|  yxl extract <book.xlsx> -o <spec.yxl.yaml> [--flat]
  #|  yxl init -o <spec.yxl.yaml> [--force]
  #|  yxl help | --help | -h
  #|  yxl version | --version | -V
  #|
  #|Options:
  #|  -o, --output <file>   where to write the workbook, or the spec
  #|      --check           validate the spec and write nothing
  #|      --set name=value  override a parameter the spec declares (repeatable)
  #|      --flat            extract into one file, writing no CSV beside it
  #|      --force           let `init` overwrite a file that already exists
  #|
  #|`init` writes a spec holding one empty sheet — somewhere to start typing,
  #|not a worked example. It refuses to overwrite an existing file.
  #|
  #|`extract` is a one-way migration aid: it recovers what the spec format can
  #|express and says what it could not, then checks its own output by compiling
  #|it back. Treat the result as a starting point, not as a copy.
  #|
  #|Exit codes:
  #|  0  success
  #|  1  the spec is invalid, or a file could not be read or written
  #|  2  the command line itself was wrong

///|
/// Parse arguments (the program name already removed) into a `Command`. A
/// malformed command line is a `@diag.CliError`.
pub fn parse_args(args : ArrayView[String]) -> Command raise @diag.CliError {
  match args {
    [] => Help
    ["help" | "--help" | "-h", ..] => Help
    ["version" | "--version" | "-V", ..] => Version
    ["build", .. rest] => parse_build(rest)
    ["extract", .. rest] => parse_extract(rest)
    ["init", .. rest] => parse_init(rest)
    [other, ..] =>
      raise usage_error(
        "unknown command '\{other}' (expected 'build', 'extract', 'init', 'help', or 'version')",
      )
  }
}

///|
fn parse_build(args : ArrayView[String]) -> Command raise @diag.CliError {
  let mut input = None
  let mut output = None
  let mut check = false
  let params : Map[String, String] = Map([])
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "-o" | "--output" => {
        guard i + 1 < args.length() else {
          raise usage_error("'\{args[i]}' needs a file argument")
        }
        guard output is None else {
          raise usage_error("'-o' was given more than once")
        }
        output = Some(args[i + 1])
        i += 2
      }
      "--check" => {
        check = true
        i += 1
      }
      "--set" => {
        guard i + 1 < args.length() else {
          raise usage_error("'--set' needs a 'name=value' argument")
        }
        let (name, value) = parse_setting(args[i + 1])
        guard !params.contains(name) else {
          raise usage_error("'--set \{name}=' was given more than once")
        }
        params[name] = value
        i += 2
      }
      option if option.has_prefix("-") =>
        raise usage_error("unknown option '\{option}'")
      positional => {
        guard input is None else {
          raise usage_error("more than one input file given")
        }
        input = Some(positional)
        i += 1
      }
    }
  }
  guard input is Some(input) else { raise usage_error("no input file given") }
  if check {
    // `--check` writes nothing, so naming an output would promise a file that
    // never appears.
    guard output is None else {
      raise usage_error("'--check' writes nothing, so it cannot take '-o'")
    }
    return Check(input~, params~)
  }
  guard output is Some(output) else {
    raise usage_error("no output file given (use -o <out.xlsx>)")
  }
  Build(input~, output~, params~)
}

///|
/// `extract <book.xlsx> -o <spec.yxl.yaml>`. Simpler than `build`: nothing to
/// parameterize, and nothing useful to do without somewhere to put the result.
fn parse_extract(args : ArrayView[String]) -> Command raise @diag.CliError {
  let mut input = None
  let mut output = None
  let mut flat = false
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--flat" => {
        flat = true
        i += 1
      }
      "-o" | "--output" => {
        guard i + 1 < args.length() else {
          raise usage_error("'\{args[i]}' needs a file argument")
        }
        guard output is None else {
          raise usage_error("'-o' was given more than once")
        }
        output = Some(args[i + 1])
        i += 2
      }
      option if option.has_prefix("-") =>
        raise usage_error("unknown option '\{option}'")
      positional => {
        guard input is None else {
          raise usage_error("more than one input file given")
        }
        input = Some(positional)
        i += 1
      }
    }
  }
  guard input is Some(input) else {
    raise usage_error("no input workbook given")
  }
  guard output is Some(output) else {
    raise usage_error("no output file given (use -o <spec.yxl.yaml>)")
  }
  Extract(input~, output~, flat~)
}

///|
/// `init -o <spec.yxl.yaml> [--force]`. Alone among the commands it reads
/// nothing, so `-o` is the whole command line — and, as with `extract`, there
/// is nothing useful to do without somewhere to put the result.
fn parse_init(args : ArrayView[String]) -> Command raise @diag.CliError {
  let mut output = None
  let mut force = false
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--force" => {
        force = true
        i += 1
      }
      "-o" | "--output" => {
        guard i + 1 < args.length() else {
          raise usage_error("'\{args[i]}' needs a file argument")
        }
        guard output is None else {
          raise usage_error("'-o' was given more than once")
        }
        output = Some(args[i + 1])
        i += 2
      }
      option if option.has_prefix("-") =>
        raise usage_error("unknown option '\{option}'")
      positional =>
        raise usage_error(
          "'init' takes no input file, but '\{positional}' was given",
        )
    }
  }
  guard output is Some(output) else {
    raise usage_error("no output file given (use -o <spec.yxl.yaml>)")
  }
  Init(output~, force~)
}

///|
/// Split a `--set` argument on its first `=`. The name must be non-empty; the
/// value may be (`--set note=` sets it to the empty string).
fn parse_setting(argument : String) -> (String, String) raise @diag.CliError {
  guard argument.split_once("=") is Some((name, value)) else {
    raise usage_error("'--set \{argument}' must be 'name=value'")
  }
  guard !name.is_empty() else {
    raise usage_error("'--set \{argument}' has no parameter name")
  }
  (name.to_owned(), value.to_owned())
}

///|
/// Compile a spec's source text into `.xlsx` bytes. This is the whole pipeline —
/// parse, load, emit — and is I/O-free, so it tests on strings and bytes.
/// `file` names the source in any diagnostic. It may raise `@diag.YamlError`,
/// `@diag.SchemaError`, or `@diag.EmitError`.
///
/// `resolve` supplies the source of any `$include` — and of a `data:` table —
/// while `read_bytes` supplies the contents of any file that is not text, which
/// today means an image. Without either, a spec that needs it is a diagnostic:
/// reading files stays the caller's job, and that is what keeps this function
/// I/O-free (ADR-003). `params` overrides the spec's declared parameter defaults
/// (the CLI's `--set`).
pub fn compile(
  source : String,
  file~ : String,
  resolve? : @loader.IncludeResolver,
  read_bytes? : @loader.BytesResolver,
  params? : Map[String, String],
) -> Bytes raise {
  @emit.to_bytes(
    @loader.load(
      @yaml.parse(source, file~),
      file~,
      resolve?,
      read_bytes?,
      params?,
    ),
  )
}

///|
/// Render a pipeline error as a message. Recognises the subdomain errors (each
/// wraps a `@diag.Diagnostic`) and falls back to `Show` otherwise.
///
/// Pass `source~` — the spec's text — to get the offending line quoted with a
/// caret under it wherever the diagnostic carries a position. Without it, or
/// where it carries none, the message is the plain single line.
pub fn error_message(err : Error, source? : String) -> String {
  let diagnostic = match err {
    @diag.YamlError(d)
    | @diag.SchemaError(d)
    | @diag.ResolveError(d)
    | @diag.EmitError(d) => Some(d)
    // A usage error is about the command line, not the spec, so it never has a
    // source position to point into. Neither does a read error: `yxl extract`
    // is given a `.xlsx`, and there is no spec text yet to quote a line from.
    @diag.CliError(d) | @diag.ReadError(d) => return d.render()
    _ => None
  }
  match (diagnostic, source) {
    (Some(d), Some(source)) => d.render_in(source)
    (Some(d), None) => d.render()
    (None, _) => err.to_string()
  }
}

///|
fn usage_error(message : String) -> @diag.CliError {
  @diag.CliError(@diag.Diagnostic(message))
}
