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
    Build(input~, output~, params~) => build(input, output, params)
    Check(input~, params~) => check(input, params)
    Version => {
      println("yxl \{@cli.version}")
      @cli.exit_ok
    }
    Help => {
      println(@cli.usage)
      @cli.exit_ok
    }
  }
}

///|
/// Compile `input` without writing anything: the whole pipeline runs, so a spec
/// that passes here is one `build` would accept.
fn check(input : String, params : Map[String, String]) -> Int {
  let source = @fs.read_file_to_string(input) catch {
    @fs.IOError(reason) => {
      report("cannot read \{input}: \{reason}")
      return @cli.exit_error
    }
  }
  (@cli.compile(
    source,
    file=input,
    resolve=read_included,
    read_bytes=read_included_bytes,
    params~,
  )
  |> ignore) catch {
    err => {
      report(@cli.error_message(err, source~))
      return @cli.exit_error
    }
  }
  report("\{input}: ok")
  @cli.exit_ok
}

///|
/// Read `input`, compile it, and write the `.xlsx` bytes to `output`.
fn build(input : String, output : String, params : Map[String, String]) -> Int {
  let source = @fs.read_file_to_string(input) catch {
    @fs.IOError(reason) => {
      report("cannot read \{input}: \{reason}")
      return @cli.exit_error
    }
  }
  let bytes = @cli.compile(
    source,
    file=input,
    resolve=read_included,
    read_bytes=read_included_bytes,
    params~,
  ) catch {
    err => {
      report(@cli.error_message(err, source~))
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
  let name = @cli.resolve_path(from, path)
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
/// Read a file the spec names but cannot hold: an image's bytes. Resolved the
/// same way as an `$include`, and, like it, the disk half of a seam the loader
/// itself never crosses (ADR-003).
fn read_included_bytes(
  from : String,
  path : String,
) -> @loader.IncludedBytes raise {
  let name = @cli.resolve_path(from, path)
  let data = @fs.read_file_to_bytes(name) catch {
    @fs.IOError(reason) =>
      raise @diag.SchemaError(
        @diag.Diagnostic::new("\{from}: cannot read '\{name}': \{reason}"),
      )
  }
  { name, data }
}

///|
/// Print one `yxl: …` line. The single place that decides where CLI messages go.
/// Everything goes to *stdout*, including diagnostics: the toolchain exposes no
/// way to write to stderr (there is no `eprintln`), so this is a limit rather
/// than an oversight. Keeping it in one function means the day that changes is a
/// one-line day.
fn report(message : String) -> Unit {
  println("yxl: \{message}")
}
