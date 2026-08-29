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
  // `args` includes the program name at index 0.
  let args = @env.args()[1:]
  let command = @cli.parse_args(args) catch {
    @diag.CliError(d) => {
      report(d.render())
      return @cli.exit_usage
    }
  }
  match command {
    Build(input~, output~, params~) => build(input, output, params)
    Check(input~, params~) => check(input, params)
    Extract(input~, output~, flat~) => extract(input, output, flat)
    Init(output~, force~) => init_spec(output, force)
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
/// Write the starter spec to `output` (#77).
///
/// Refuses a file that is already there unless `--force` says otherwise: the
/// worst thing this command could do is overwrite a spec someone has worked on,
/// and it has no way to tell that file from one of its own.
///
/// Not named `init` for the command it serves: `fn init` is MoonBit's package
/// initializer, which takes no arguments and returns nothing.
fn init_spec(output : String, force : Bool) -> Int {
  if !force && @fs.path_exists(output) {
    report("\{output} already exists (use --force to overwrite)")
    return @cli.exit_error
  }
  @fs.write_string_to_file(output, @cli.starter_spec(output~)) catch {
    @fs.IOError(reason) => {
      report("cannot write \{output}: \{reason}")
      return @cli.exit_error
    }
  }
  report("wrote \{output}")
  @cli.exit_ok
}

///|
/// Read a workbook and write the spec that would rebuild it (ADR-017).
///
/// Everything the schema could not carry is printed, and so is anything the
/// self-check found: the spec is still written in that case, because a starting
/// point with a known gap is more use than no starting point, but the exit code
/// says it needs a look.
fn extract(input : String, output : String, flat : Bool) -> Int {
  let bytes = @fs.read_file_to_bytes(input) catch {
    @fs.IOError(reason) => {
      report("cannot read \{input}: \{reason}")
      return @cli.exit_error
    }
  }
  let extracted = @cli.extract(bytes, file=input, flat~) catch {
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
  // The spec names these by a path relative to itself, which is where they have
  // to land for `yxl build` to find them again.
  for companion in extracted.companions {
    let path = @cli.resolve_path(output, companion.path)
    guard write_companion(path, companion.content) else {
      return @cli.exit_error
    }
    report("     + \{path}")
  }
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
/// Write one of the files an extracted spec names, making the directory it sits
/// in first — the spec puts its tables under `data/`, which will not exist in a
/// directory nobody has extracted into before.
fn write_companion(path : String, content : Bytes) -> Bool {
  if @cli.directory_of(path) is Some(directory) {
    @fs.create_dir(directory) catch {
      // Already there is the ordinary case, not a failure; a directory that
      // genuinely cannot be made shows up as the write failing next.
      _ => ()
    }
  }
  @fs.write_bytes_to_file(path, content) catch {
    @fs.IOError(reason) => {
      report("cannot write \{path}: \{reason}")
      return false
    }
  }
  true
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
  { name, source, }
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
  { name, data, }
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
    @diag.Diagnostic("\{from}: cannot read '\{name}': \{reason}"),
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
