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
      println("yxl: \{d.render()}")
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
      println("yxl: cannot read \{input}: \{reason}")
      return @cli.exit_error
    }
  }
  let bytes = @cli.compile(source, file=input) catch {
    err => {
      println("yxl: \{@cli.error_message(err)}")
      return @cli.exit_error
    }
  }
  @fs.write_bytes_to_file(output, bytes) catch {
    @fs.IOError(reason) => {
      println("yxl: cannot write \{output}: \{reason}")
      return @cli.exit_error
    }
  }
  println("yxl: wrote \{output}")
  @cli.exit_ok
}
