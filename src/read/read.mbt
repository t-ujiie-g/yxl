// The reader seam: `.xlsx` bytes back into a `model.Workbook`, so `yxl extract`
// can render one as a spec (ADR-017). The mirror of `emit`, and the only other
// place the Excel backend is touched.
//
// The boundary is the **schema**, not the file: recover what `model` can hold,
// never guess at what it cannot, and record every drop so the caller can say
// what was lost. Recovering everything would be a round trip by another route,
// which §2 rules out.

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
  for name in backend.get_sheet_list() {
    let sheet = workbook.add_sheet(
      name,
      visibility=read_visibility(backend, name),
    )
    read_cells(backend, sheet, styles, notes)
    read_merges(backend, sheet)
    read_bands(backend, sheet, styles, notes)
    read_presentation(backend, sheet)
    read_decorations(backend, sheet, dates, notes)
    read_sheet_protection(backend, sheet, notes)
  }
  // The tab Excel opens on. Index 0 is the default, and saying so adds nothing.
  let active = backend.get_active_sheet_index()
  if active > 0 && backend.get_sheet_name(active) is Some(name) {
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
  let dimension = backend.get_sheet_dimension(sheet_name)
  guard !dimension.is_empty() else { return None }
  let (left, right) = match dimension.split_once(":") {
    Some((left, right)) => (left.to_owned(), right.to_owned())
    None => (dimension, dimension)
  }
  guard @units.CellRef::parse_a1(left) is Some(first) &&
    @units.CellRef::parse_a1(right) is Some(second) else {
    return None
  }
  let (top_left, bottom_right) = @units.CellRef::rect(first, second)
  Some({ top_left, bottom_right })
}

///|
/// A sheet's merged regions.
fn read_merges(backend : @xlsx.Workbook, sheet : @model.Sheet) -> Unit raise {
  for reference in backend.get_merge_cells(sheet.name) {
    if parse_range(reference) is Some(range) {
      sheet.merge(range.top_left, range.bottom_right)
    }
  }
}

///|
/// A `TopLeft:BottomRight` range as the backend spells it. Unparseable input is
/// `None` rather than an error: this is a *reader*, and a region it cannot make
/// sense of is one more thing the schema will not carry.
fn parse_range(reference : String) -> @model.CellRange? {
  guard reference.split_once(":") is Some((left, right)) else { return None }
  guard @units.CellRef::parse_a1(left.to_owned()) is Some(first) &&
    @units.CellRef::parse_a1(right.to_owned()) is Some(second) else {
    return None
  }
  let (top_left, bottom_right) = @units.CellRef::rect(first, second)
  Some({ top_left, bottom_right })
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
