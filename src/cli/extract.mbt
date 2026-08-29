///|
/// What `extract` produced: the spec text, whatever files it refers to, and the
/// honest account of what the schema could not carry.
///
/// `dropped` names each kind of loss once, whatever the file did a hundred
/// times. `warnings` is different — it holds the ways the *result* failed to
/// check out, which should be empty and is the one thing worth reading twice.
///
/// `companions` are the files the spec names, keyed by the path it names them
/// by — relative to the spec, as `docs/spec.md` §9 resolves them. Writing them
/// is the caller's job, which is what keeps `extract` I/O-free (ADR-003).
pub struct Extracted {
  spec : String
  companions : Array[Companion]
  dropped : Array[String]
  warnings : Array[String]
}

///|
/// One file the extracted spec refers to: a `data:` table, or a picture.
///
/// The content is `Bytes` for both. A CSV is text and could have been a
/// `String`, but a picture cannot, and one kind of companion is easier to write
/// out than two — the caller opens a file and writes bytes either way.
pub struct Companion {
  path : String
  content : Bytes
}

///|
/// Turn an existing workbook into the spec that would rebuild it.
///
/// This is a **one-way migration aid**, not a round trip: what the schema can
/// say is recovered, what it cannot is dropped and named. See ADR-017 for where
/// that boundary is and why it is the schema rather than a list of features.
///
/// The result is **verified, not trusted**. Compression and naming are both
/// inferences, so the spec is compiled back here and the cells compared against
/// the ones read out of the original; anything that does not match is reported
/// in `warnings` rather than left for the author to discover in Excel. Both
/// halves of the pipeline are already in memory, which is what makes checking
/// cheap enough to do every time.
pub fn extract(
  bytes : Bytes,
  file~ : String,
  flat? : Bool = false,
) -> Extracted raise {
  let recovered = @read.from_bytes(bytes)
  // A block of plain values reads better as a table beside the spec than as a
  // thousand `cells:` lines — but it is a *second file*, so `--flat` keeps
  // everything in one, which is what a reader comparing two extractions wants.
  let tables = if flat { [] } else { @render.data_tables(recovered.workbook) }
  // A picture is not an inference: the model holds its bytes because the
  // workbook did, and there is no way to put them in a YAML file. `--flat` has
  // nothing to say about it, so it does not.
  let pictures = @render.pictures(recovered.workbook)
  let spec = @yaml.write(
    @render.workbook(recovered.workbook, tables~, pictures~),
  )
  let companions = []
  for table in tables {
    companions.push(
      ({ path: table.path, content: @utf8.encode(table.csv), } : Companion),
    )
  }
  for picture in pictures {
    companions.push({ path: picture.path, content: picture.content, })
  }
  {
    spec,
    companions,
    dropped: recovered.dropped,
    warnings: verify(spec, companions, recovered, file~),
  }
}

///|
/// Compile the rendered spec and compare what comes out against what went in.
///
/// The comparison is on the *model*, not on bytes: two workbooks that differ
/// only in the order Excel happens to write a part are the same spreadsheet, and
/// a byte comparison would report that as a failure every time. Cells are what a
/// reader cares about and what an inference could get wrong, so cells are what
/// is checked.
fn verify(
  spec : String,
  companions : Array[Companion],
  recovered : @read.Recovered,
  file~ : String,
) -> Array[String] {
  let warnings = []
  // The spec names its companions by path, so the check has to resolve them the
  // way the CLI will — from memory here, since nothing has been written yet.
  let by_path : Map[String, Bytes] = Map([])
  for companion in companions {
    by_path[companion.path] = companion.content
  }
  let resolve : @loader.IncludeResolver = fn(_from, path) {
    {
      name: path,
      source: match by_path.get(path) {
        Some(content) => @utf8.decode_lossy(content[:])
        None => ""
      },
    }
  }
  // A picture is read through the other resolver, as bytes, because that is what
  // it is; decoding it as text and back would not survive.
  let read_bytes : @loader.BytesResolver = fn(_from, path) {
    { name: path, data: by_path.get(path).unwrap_or(b""), }
  }
  let rebuilt = @read.from_bytes(
      @emit.to_bytes(
        @loader.load(@yaml.parse(spec, file~), file~, resolve~, read_bytes~),
      ),
    ).workbook catch {
      err => {
        warnings.push(
          "the extracted spec did not compile: \{error_message(err)} — please report this, and use the spec as a starting point rather than as-is",
        )
        return warnings
      }
    }
  let before = recovered.workbook
  if rebuilt.sheets.length() != before.sheets.length() {
    warnings.push(
      "the extracted spec rebuilds \{rebuilt.sheets.length()} sheets, not \{before.sheets.length()}",
    )
    return warnings
  }
  for index, sheet in before.sheets {
    let after = rebuilt.sheets[index]
    for difference in compare_cells(sheet, after) {
      warnings.push(difference)
    }
  }
  warnings
}

///|
/// Where two sheets' cells disagree, worst-first and capped: a reader needs to
/// know *that* the check failed and roughly where, and a thousand lines of it
/// would bury both.
fn compare_cells(before : @model.Sheet, after : @model.Sheet) -> Array[String] {
  let differences = []
  let rebuilt : Map[String, @model.CellValue] = Map([])
  for cell in after.cells {
    rebuilt[cell.pos.to_a1()] = cell.value
  }
  for cell in before.cells {
    let reference = cell.pos.to_a1()
    match rebuilt.get(reference) {
      Some(value) =>
        if value != cell.value {
          differences.push(
            "sheet '\{before.name}' cell '\{reference}' rebuilds to a different value",
          )
        }
      None =>
        differences.push(
          "sheet '\{before.name}' cell '\{reference}' is missing from the rebuilt workbook",
        )
    }
    if differences.length() >= MAX_REPORTED_DIFFERENCES {
      differences.push("… and possibly more; only the first few are listed")
      return differences
    }
  }
  differences
}

///|
/// How many mismatches to name before saying "and more". One is a bug worth
/// chasing; a thousand is the same bug, listed a thousand times.
const MAX_REPORTED_DIFFERENCES : Int = 5
