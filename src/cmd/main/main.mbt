///|
/// Entry point: `yxl build <in.yaml> -o <out.xlsx>`. Filesystem access and the
/// process exit code live only here (ADR-003); the compile pipeline behind
/// `@cli` is I/O-free.
fn main {
  @sys.exit(run())
}

///|
/// Parse arguments, run the requested command, and return a process exit code.
fn run() -> Int {
  // `get_cli_args` includes the program name at index 0.
  let args = @sys.get_cli_args()[1:]
  let command = @cli.parse_args(args) catch {
    @diag.CliError(d) => {
      report(d.render())
      return @cli.exit_usage
    }
  }
  match command {
    Build(input~, output~) => build(input, output)
  }
}

///|
/// Read `input`, compile it, and write the `.xlsx` bytes to `output`.
fn build(input : String, output : String) -> Int {
  let source = @fs.read_file_to_string(input) catch {
    @fs.IOError(reason) => {
      report("cannot read \{input}: \{reason}")
      return @cli.exit_error
    }
  }
  let bytes = @cli.compile(source, file=input, resolve=read_included) catch {
    err => {
      report(@cli.error_message(err))
      return @cli.exit_error
    }
  }
  @fs.write_bytes_to_file(output, bytes) catch {
    @fs.IOError(reason) => {
      report("cannot write \{output}: \{reason}")
      return @cli.exit_error
    }
  }
  report("wrote \{output}")
  @cli.exit_ok
}

///|
/// Read the file an `$include` names, relative to the file containing it, so a
/// spec can be moved as a directory. This is the disk half of includes; the
/// loader itself never opens a file (ADR-003).
fn read_included(from : String, path : String) -> @loader.Included raise {
  let name = resolve_path(from, path)
  let source = @fs.read_file_to_string(name) catch {
    @fs.IOError(reason) =>
      raise @diag.SchemaError(
        @diag.Diagnostic::new(
          "\{from}: cannot read included file '\{name}': \{reason}",
        ),
      )
  }
  { name, source }
}

///|
/// A path written in `from`, resolved against the directory `from` sits in: an
/// include in `specs/report.yaml` naming `data/q3.yaml` means
/// `specs/data/q3.yaml`. An absolute path is taken as it stands.
fn resolve_path(from : String, path : String) -> String {
  if path.has_prefix("/") {
    return path
  }
  match from.rev_find("/") {
    Some(slash) => from[:slash + 1].to_owned() + path
    None => path
  }
}

///|
/// Print one `yxl: …` line. The single place that decides where CLI messages go
/// (routing errors to stderr is a later refinement).
fn report(message : String) -> Unit {
  println("yxl: \{message}")
}
