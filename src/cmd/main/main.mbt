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
  let bytes = @cli.compile(source, file=input) catch {
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
/// Print one `yxl: …` line. The single place that decides where CLI messages go
/// (routing errors to stderr is a later refinement).
fn report(message : String) -> Unit {
  println("yxl: \{message}")
}
