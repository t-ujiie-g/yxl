// The other direction of the pipeline: `.xlsx` bytes -> a spec (ADR-017).
// I/O-free like `compile`, so it tests on bytes and strings.

///|
/// What `extract` produced: the spec text, and the honest account of what the
/// schema could not carry.
///
/// `dropped` names each kind of loss once, whatever the file did a hundred
/// times. `warnings` is different — it holds the ways the *result* failed to
/// check out, which should be empty and is the one thing worth reading twice.
pub struct Extracted {
  spec : String
  dropped : Array[String]
  warnings : Array[String]
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
pub fn extract(bytes : Bytes, file~ : String) -> Extracted raise {
  let recovered = @read.from_bytes(bytes)
  let spec = @yaml.write(@render.workbook(recovered.workbook))
  { spec, dropped: recovered.dropped, warnings: verify(spec, recovered, file~) }
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
  recovered : @read.Recovered,
  file~ : String,
) -> Array[String] {
  let warnings = []
  let rebuilt = @read.from_bytes(
      @emit.to_bytes(@loader.load(@yaml.parse(spec, file~), file~)),
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
