// Process exit codes. Stable across releases (Phase 8 formalises the full set);
// 2 for a usage/argument error is the common Unix convention.

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
/// A parsed command line. Only `build` exists today.
pub(all) enum Command {
  Build(input~ : String, output~ : String)
} derive(Eq, Debug)

///|
/// Parse arguments (the program name already removed) into a `Command`. A
/// malformed command line is a `@diag.CliError`.
pub fn parse_args(args : ArrayView[String]) -> Command raise @diag.CliError {
  match args {
    [] =>
      raise usage_error(
        "no command given (usage: yxl build <in.yaml> -o <out.xlsx>)",
      )
    ["build", .. rest] => parse_build(rest)
    [other, ..] =>
      raise usage_error("unknown command '\{other}' (expected 'build')")
  }
}

///|
fn parse_build(args : ArrayView[String]) -> Command raise @diag.CliError {
  let mut input = None
  let mut output = None
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
  let input = match input {
    Some(input) => input
    None => raise usage_error("no input file given")
  }
  let output = match output {
    Some(output) => output
    None => raise usage_error("no output file given (use -o <out.xlsx>)")
  }
  Build(input~, output~)
}

///|
/// Compile a spec's source text into `.xlsx` bytes. This is the whole pipeline —
/// parse, load, emit — and is I/O-free, so it tests on strings and bytes.
/// `file` names the source in any diagnostic. It may raise `@diag.YamlError`,
/// `@diag.SchemaError`, or `@diag.EmitError`.
pub fn compile(source : String, file~ : String) -> Bytes raise {
  @emit.to_bytes(@loader.load(@yaml.parse(source, file~), file~))
}

///|
/// Render a pipeline error as a one-line message. Recognises the subdomain
/// errors (each wraps a `@diag.Diagnostic`) and falls back to `Show` otherwise.
pub fn error_message(err : Error) -> String {
  match err {
    @diag.YamlError(d) => d.render()
    @diag.SchemaError(d) => d.render()
    @diag.EmitError(d) => d.render()
    @diag.CliError(d) => d.render()
    _ => err.to_string()
  }
}

///|
fn usage_error(message : String) -> @diag.CliError {
  @diag.CliError(@diag.Diagnostic::new(message))
}
