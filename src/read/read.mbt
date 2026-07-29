// The reader seam: `.xlsx` bytes back into a `model.Workbook`, so `yxl extract`
// can render one as a spec (ADR-017). The mirror of `emit`, and the only other
// place the Excel backend is touched.
//
// The boundary is the **schema**, not the file: recover what `model` can hold,
// never guess at what it cannot, and record every drop so the caller can say
// what was lost. Recovering everything would be a round-trip contract by
// another route, which this direction deliberately does not offer (ADR-017).

///|
/// What one read produced: the workbook, and a note for everything in the file
/// that the schema has no words for.
///
/// `dropped` is not a warning list to be skimmed — it is the honest half of a
/// lossy conversion, and `yxl extract` prints it.
pub struct Recovered {
  workbook : @model.Workbook
  dropped : Array[String]
}

///|
/// The reader seam (ADR-017): turn `.xlsx` bytes into a model. Every backend
/// access lives behind this interface, so the pipeline never calls the Excel
/// library directly and the backend stays swappable in both directions.
pub trait Reader {
  fn read(Self, Bytes) -> Recovered raise @diag.ReadError
}

///|
/// The `bobzhang/mbtexcel`-backed reader — the one place `@xlsx` is read from.
pub struct MbtexcelReader {}

///|
/// The default reader.
pub fn MbtexcelReader::new() -> MbtexcelReader {
  MbtexcelReader::{  }
}

///|
pub impl Reader for MbtexcelReader with fn read(_self, bytes) {
  recover(bytes) catch {
    @diag.ReadError(_) as ours => raise ours
    err => {
      // Upcast to `Error` for its `Show`; the concrete `XlsxError` has none.
      let reason : Error = err
      raise @diag.ReadError(
        @diag.Diagnostic::new("Excel backend: " + reason.to_string()),
      )
    }
  }
}

///|
/// Read `.xlsx` bytes into a model using the default backend — the convenient
/// entry point when a caller does not care which backend is used.
pub fn from_bytes(bytes : Bytes) -> Recovered raise @diag.ReadError {
  MbtexcelReader::new().read(bytes)
}

///|
/// Walk the backend's workbook into ours. Raises the backend's own error, which
/// the seam boundary wraps.
fn recover(bytes : Bytes) -> Recovered raise {
  let backend = @xlsx.read(bytes[:])
  let notes = Notes::new()
  let dates : @units.DateSystem = if backend.get_workbook_props().date_1904
    is Some(true) {
    Date1904
  } else {
    Date1900
  }
  let workbook = @model.Workbook::new(
    date_system=dates,
    default_font?=read_default_font(backend),
  )
  let styles = StyleTable::new()
  read_workbook_keys(backend, workbook, notes)
  let sheet_names = backend.get_sheet_list()
  // A chart sheet is a whole tab that is one chart, and `get_sheet_list` names
  // it alongside the worksheets while every per-sheet accessor answers
  // `SheetNotFound` for it. Walking it as a grid used to fail the whole read
  // with the backend's own error and nothing to act on. It is skipped and said
  // aloud instead: recovering it as an empty sheet would claim a data tab the
  // workbook does not have.
  let worksheets = sheet_names.filter(name => {
    if backend.sheet(name) is Some(_) {
      true
    } else {
      // Which kind it is comes off the backend rather than off the assumption
      // that a non-worksheet must be a chart sheet: Excel also has dialog and
      // macro sheets, and calling one of those a chart would be a confident
      // wrong answer where "not a grid" is a true one.
      notes.drop(
        if backend.chart_sheet(name) is Some(_) {
          "the sheet '\{name}', which is a chart sheet rather than a grid — the spec has no way to declare one, and the chart on it is raw XML besides"
        } else {
          "the sheet '\{name}', which is not a worksheet — the spec declares grids, and the backend offers nothing to read this one as"
        },
      )
      false
    }
  })
  for name in worksheets {
    let sheet = workbook.add_sheet(
      name,
      visibility=read_visibility(backend, name),
    )
    read_cells(backend, sheet, styles, notes)
    read_merges(backend, sheet)
    read_bands(backend, sheet, styles, notes)
    read_presentation(backend, sheet)
    read_decorations(backend, sheet, dates, notes)
    read_images(backend, sheet, notes)
    read_controls(backend, sheet, notes)
    read_slicers(backend, sheet, notes)
    read_shapes(backend, sheet, notes)
    read_sparklines(
      backend,
      sheet,
      qualified_ranges=worksheets.length() > 1,
      notes,
    )
    read_sheet_protection(backend, sheet, notes)
    read_unsupported(backend, sheet, notes)
  }
  // The tab Excel opens on. Index 0 is the default, and saying so adds nothing —
  // and a chart sheet that was skipped above is no longer a tab this spec has,
  // so naming it would produce one the loader refuses.
  let active = backend.get_active_sheet_index()
  if active > 0 &&
    backend.get_sheet_name(active) is Some(name) &&
    worksheets.contains(name) {
    workbook.set_active_sheet(name)
  }
  { workbook, dropped: notes.take() }
}

///|
/// Whether a sheet shows, hides, or hides so hard Excel's own dialog will not
/// bring it back. `get_sheet_visible` answers the first question only, so the
/// third state is read off the worksheet's own record.
fn read_visibility(
  backend : @xlsx.Workbook,
  name : String,
) -> @model.SheetVisibility raise {
  if backend.get_sheet_visible(name) {
    return Visible
  }
  match backend.sheet(name) {
    Some(source) =>
      match source.state {
        VeryHidden => VeryHidden
        _ => Hidden
      }
    None => Hidden
  }
}

///|
/// The used range of a sheet, as the backend records it, or `None` for a sheet
/// with nothing in it. The dimension is `A1:D7`, or a bare `A1` when a single
/// cell is populated.
fn used_range(
  backend : @xlsx.Workbook,
  sheet_name : String,
) -> @model.CellRange? raise {
  @model.CellRange::parse_loose(backend.get_sheet_dimension(sheet_name))
}

///|
/// A sheet's merged regions.
fn read_merges(backend : @xlsx.Workbook, sheet : @model.Sheet) -> Unit raise {
  for reference in backend.get_merge_cells(sheet.name) {
    if @model.CellRange::parse(reference) is Some(range) {
      sheet.merge(range.top_left, range.bottom_right)
    }
  }
}

///|
/// Everything the file says that the schema cannot, collected in the order it
/// was met and deduplicated — a workbook with a gradient fill on 400 cells
/// should say so once.
priv struct Notes {
  seen : Map[String, Unit]
  order : Array[String]
}

///|
fn Notes::new() -> Notes {
  { seen: Map([]), order: [] }
}

///|
/// Record that something was dropped. Repeats are folded together.
fn Notes::drop(self : Notes, note : String) -> Unit {
  if self.seen.get(note) is None {
    self.seen[note] = ()
    self.order.push(note)
  }
}

///|
fn Notes::take(self : Notes) -> Array[String] {
  self.order
}
