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
    Extract(input~, output~) => extract(input, output)
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
  guard read_source(input) is Some(source) else { return @cli.exit_error }
  guard compile(input, source, params) is Some(_) else {
    return @cli.exit_error
  }
  report("\{input}: ok")
  @cli.exit_ok
}

///|
/// Read `input`, compile it, and write the `.xlsx` bytes to `output`.
fn build(input : String, output : String, params : Map[String, String]) -> Int {
  guard read_source(input) is Some(source) else { return @cli.exit_error }
  guard compile(input, source, params) is Some(bytes) else {
    return @cli.exit_error
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
/// Run the whole pipeline over a spec already read, wiring in the two disk-side
/// resolvers. A failure is reported against the source — so the offending line
/// is quoted — and returns `None`. `build` and `check` differ only in what they
/// do with the bytes that come back.
fn compile(
  input : String,
  source : String,
  params : Map[String, String],
) -> Bytes? {
  Some(
    @cli.compile(
      source,
      file=input,
      resolve=read_included,
      read_bytes=read_included_bytes,
      params~,
    ),
  ) catch {
    err => {
      report(@cli.error_message(err, source~))
      None
    }
  }
}

///|
/// Read a workbook and write the spec that would rebuild it (ADR-017).
///
/// Everything the schema could not carry is printed, and so is anything the
/// self-check found: the spec is still written in that case, because a starting
/// point with a known gap is more use than no starting point, but the exit code
/// says it needs a look.
fn extract(input : String, output : String) -> Int {
  let bytes = @fs.read_file_to_bytes(input) catch {
    @fs.IOError(reason) => {
      report("cannot read \{input}: \{reason}")
      return @cli.exit_error
    }
  }
  let extracted = @cli.extract(bytes, file=input) catch {
    err => {
      report(@cli.error_message(err))
      return @cli.exit_error
    }
  }
  @fs.write_string_to_file(output, extracted.spec) catch {
    @fs.IOError(reason) => {
      report("cannot write \{output}: \{reason}")
      return @cli.exit_error
    }
  }
  report("wrote \{output}")
  for note in extracted.dropped {
    report("  dropped: \{note}")
  }
  guard extracted.warnings.is_empty() else {
    report("the extracted spec did not rebuild the workbook exactly:")
    for warning in extracted.warnings {
      report("  \{warning}")
    }
    return @cli.exit_error
  }
  if !extracted.dropped.is_empty() {
    report("everything else rebuilds the workbook as read")
  }
  @cli.exit_ok
}

///|
/// Read the spec itself, reporting a failure and returning `None` — the shared
/// front door of `build` and `check`.
fn read_source(input : String) -> String? {
  Some(@fs.read_file_to_string(input)) catch {
    @fs.IOError(reason) => {
      report("cannot read \{input}: \{reason}")
      None
    }
  }
}

///|
/// Read the file an `$include` names, relative to the file containing it, so a
/// spec can be moved as a directory. This is the disk half of includes; the
/// loader itself never opens a file (ADR-003).
fn read_included(from : String, path : String) -> @loader.Included raise {
  let name = @cli.resolve_path(from, path)
  let source = @fs.read_file_to_string(name) catch {
    @fs.IOError(reason) => raise read_error(from, name, reason)
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
    @fs.IOError(reason) => raise read_error(from, name, reason)
  }
  { name, data }
}

///|
/// The one wording for "a file the spec names could not be read", whether it
/// held YAML or bytes.
fn read_error(
  from : String,
  name : String,
  reason : String,
) -> @diag.SchemaError {
  @diag.SchemaError(
    @diag.Diagnostic::new("\{from}: cannot read '\{name}': \{reason}"),
  )
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
