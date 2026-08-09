///|
/// Render a workbook as the spec that would compile to it.
///
/// The result is a `@yaml.Node`, not text: `@yaml.write` decides quoting and
/// layout, and a caller that wants to check the spec before writing it can load
/// this straight back (which is what `yxl extract` does — ADR-017).
pub fn workbook(
  wb : @model.Workbook,
  tables? : Array[DataTable] = [],
  pictures? : Array[Picture] = [],
) -> @yaml.Node {
  let by_sheet : Map[String, DataTable] = Map([])
  for table in tables {
    by_sheet[table.sheet] = table
  }
  // Looked up by where each picture sits rather than by the order it was built,
  // so the spec and the files agree without either depending on the other's
  // iteration order.
  let picture_paths : Map[String, String] = Map([])
  for picture in pictures {
    picture_paths[Picture::key(picture.sheet, picture.at)] = picture.path
  }
  let root = []
  if wb.date_system is Date1904 {
    root.push(("date1904", @yaml.Bool(true)))
  }
  if wb.default_font is Some(name) {
    root.push(("default_font", @yaml.Str(name)))
  }
  if wb.active_sheet is Some(name) {
    root.push(("active", @yaml.Str(name)))
  }
  if wb.properties is Some(properties) {
    root.push(("properties", document_properties(properties)))
  }
  if wb.calc is Some(calc) {
    root.push(("calc", calc_settings(calc)))
  }
  let styles = StyleNames::of(wb)
  let defs = []
  if !styles.declared.is_empty() {
    let entries = []
    for declared in styles.declared {
      entries.push((declared.0, style(declared.1)))
    }
    defs.push(("styles", @yaml.Map(entries)))
  }
  for block in defined_names(wb) {
    defs.push(block)
  }
  if !defs.is_empty() {
    root.push(("defs", @yaml.Map(defs)))
  }
  let sheets = []
  for sheet in wb.sheets {
    sheets.push(
      one_sheet(sheet, styles, by_sheet.get(sheet.name), picture_paths),
    )
  }
  root.push(("sheets", @yaml.Seq(sheets)))
  @yaml.Map(root)
}

///|
/// One sheet, its keys in the order `docs/spec.md` presents them — what the
/// sheet *is*, then what is in it, then how it looks and prints.
fn one_sheet(
  sheet : @model.Sheet,
  styles : StyleNames,
  table : DataTable?,
  picture_paths : Map[String, String],
) -> @yaml.Node {
  let entries = [("name", @yaml.Str(sheet.name))]
  match sheet.visibility {
    Visible => ()
    Hidden => entries.push(("visibility", @yaml.Str("hidden")))
    VeryHidden => entries.push(("visibility", @yaml.Str("very_hidden")))
  }
  // A region pulled out to a file leaves its cells behind; whatever the sheet
  // holds outside it still goes in `cells:`.
  let covered = match table {
    Some(table) => table.covered
    None => @set.Set::Set([])
  }
  if sheet.cells.iter().any(cell => !covered.contains(cell.pos.to_a1())) {
    entries.push(("cells", cells(sheet, styles, covered)))
  }
  if table is Some(table) {
    entries.push(
      (
        "data",
        @yaml.Seq([
          @yaml.Map([
            ("at", @yaml.Str(table.at.to_a1())),
            ("csv", @yaml.Str(table.path)),
          ]),
        ]),
      ),
    )
  }
  if !sheet.formulas.is_empty() {
    let ranges = []
    for range in sheet.formulas {
      ranges.push(
        @yaml.Map([
          ("at", @yaml.Str(range.at.to_a1())),
          ("formula", @yaml.Str(range.formula)),
        ]),
      )
    }
    entries.push(("formulas", @yaml.Seq(ranges)))
  }
  if !sheet.columns.is_empty() {
    entries.push(("columns", bands(sheet.columns, styles, down=false)))
  }
  if !sheet.rows.is_empty() {
    entries.push(("rows", bands(sheet.rows, styles, down=true)))
  }
  if !sheet.merges.is_empty() {
    let ranges = []
    for merge in sheet.merges {
      ranges.push(@yaml.Str(merge.to_a1()))
    }
    entries.push(("merges", @yaml.Seq(ranges)))
  }
  match sheet.panes {
    Some(Freeze(at)) => entries.push(("freeze", @yaml.Str(at.to_a1())))
    Some(Split(x~, y~)) =>
      entries.push(("split", @yaml.Map([("x", number(x)), ("y", number(y))])))
    None => ()
  }
  if sheet.gridlines is Some(shown) {
    entries.push(("gridlines", @yaml.Bool(shown)))
  }
  if sheet.tab_color is Some(color) {
    entries.push(("tab_color", @yaml.Str(color.hex())))
  }
  if !sheet.images.is_empty() {
    entries.push(("images", images(sheet, picture_paths)))
  }
  if sheet.background is Some(_) {
    match picture_paths.get(Picture::key(sheet.name, None)) {
      Some(path) => entries.push(("background", @yaml.Str(path)))
      None => ()
    }
  }
  decorations(sheet, entries)
  if !sheet.charts.is_empty() {
    entries.push(("charts", charts(sheet)))
  }
  if !sheet.shapes.is_empty() {
    entries.push(("shapes", shapes(sheet)))
  }
  if !sheet.sparklines.is_empty() {
    entries.push(("sparklines", sparklines(sheet)))
  }
  if !sheet.controls.is_empty() {
    entries.push(("controls", controls(sheet)))
  }
  if !sheet.slicers.is_empty() {
    entries.push(("slicers", slicers(sheet)))
  }
  if sheet.page is Some(page) {
    entries.push(("print", print_setup(page)))
  }
  if sheet.protection is Some(protection) {
    entries.push(("protect", sheet_protection(protection)))
  }
  @yaml.Map(entries)
}

///|
/// A sheet's cells, keyed by address in reading order — left to right, top to
/// bottom — rather than in the order the model happened to collect them. The
/// model keeps insertion order, which for a recovered workbook is already the
/// scan order, but a spec is read by a person and a jumbled `cells:` block is
/// the first thing that would make one close the file.
fn cells(
  sheet : @model.Sheet,
  styles : StyleNames,
  covered : @set.Set[String],
) -> @yaml.Node {
  let ordered = sheet.cells.filter(cell => !covered.contains(cell.pos.to_a1()))
  ordered.sort_by((left, right) => {
    if left.pos.row != right.pos.row {
      left.pos.row - right.pos.row
    } else {
      left.pos.col - right.pos.col
    }
  })
  let entries = []
  for cell in ordered {
    entries.push((cell.pos.to_a1(), one_cell(cell, styles)))
  }
  @yaml.Map(entries)
}

///|
/// One cell: the bare scalar where that says everything, and the expanded
/// mapping where it does not.
fn one_cell(cell : @model.Cell, styles : StyleNames) -> @yaml.Node {
  // A number format is a *sibling* of `style:` on a cell, not a key inside it
  // (`docs/spec.md` §3), so a style that is nothing but a format goes out as a
  // bare `format:` and leaves the cell without a style at all.
  let (style_node, format) = styles.split(cell.style)
  match (cell.value, style_node, format) {
    (Text(text), None, None) => @yaml.Str(text)
    (Number(number), None, None) => number_scalar(number)
    (Bool(flag), None, None) => @yaml.Bool(flag)
    _ => {
      let entries = []
      match cell.value {
        Text(text) => entries.push(("value", @yaml.Str(text)))
        Number(number) => entries.push(("value", number_scalar(number)))
        Bool(flag) => entries.push(("value", @yaml.Bool(flag)))
        Date(datetime) => {
          entries.push(("value", @yaml.Str(date_text(datetime))))
          entries.push(("type", @yaml.Str("date")))
        }
        Error(text) => {
          entries.push(("value", @yaml.Str(text)))
          entries.push(("type", @yaml.Str("error")))
        }
        Formula(formula~, cached~) => {
          entries.push(("formula", @yaml.Str(formula)))
          if cached is Some(value) && cached_scalar(value) is Some(node) {
            entries.push(("value", node))
          }
        }
        RichText(runs) => {
          let rendered = []
          for run in runs {
            rendered.push(rich_run(run))
          }
          entries.push(("rich", @yaml.Seq(rendered)))
        }
        // Nothing to say about what the cell holds — the `style:` or `format:`
        // below is the whole entry, which is what a style-only cell is.
        Blank => ()
      }
      if format is Some(code) {
        entries.push(("format", @yaml.Str(code)))
      }
      if style_node is Some(node) {
        entries.push(("style", node))
      }
      @yaml.Map(entries)
    }
  }
}

///|
/// A formula's cached result, where it is a scalar the `value:` key can hold.
fn cached_scalar(value : @model.CellValue) -> @yaml.Node? {
  match value {
    Text(text) => Some(@yaml.Str(text))
    Number(number) => Some(number_scalar(number))
    Bool(flag) => Some(@yaml.Bool(flag))
    _ => None
  }
}

///|
/// One rich-text run: the bare string where it wears no font of its own.
fn rich_run(run : @model.RichRun) -> @yaml.Node {
  match run.font {
    None => @yaml.Str(run.text)
    Some(font) =>
      @yaml.Map([("text", @yaml.Str(run.text)), ("font", font_node(font))])
  }
}

///|
/// A whole number goes out as an integer, so a spec reads `2400000` rather than
/// `2400000.0`. The value is the same either way; the spelling is not.
///
/// The bound is where a `Double` stops being able to tell one integer from the
/// next: past it, `2^53 + 1` and `2^53` are the same value, and writing either
/// as an integer would claim a precision the number does not have.
fn number_scalar(number : Double) -> @yaml.Node {
  if number == number.trunc() &&
    number.abs() <= EXACT_INTEGER_LIMIT &&
    !number.is_inf() {
    @yaml.Int(number.to_int64())
  } else {
    @yaml.Float(number)
  }
}

///|
/// The largest magnitude a `Double` represents every integer up to: 2^53.
const EXACT_INTEGER_LIMIT : Double = 9007199254740992.0

///|
/// The same rule for a measurement that reached the model as a `Double`.
fn number(value : Double) -> @yaml.Node {
  number_scalar(value)
}

///|
/// A date/time in the spelling `type: date` accepts.
fn date_text(datetime : @units.DateTime) -> String {
  let date = "\{pad4(datetime.year)}-\{pad2(datetime.month)}-\{pad2(datetime.day)}"
  if datetime.has_time() {
    "\{date} \{pad2(datetime.hour)}:\{pad2(datetime.minute)}:\{pad2(datetime.second)}"
  } else {
    date
  }
}

///|
fn pad2(value : Int) -> String {
  value.to_string().pad_start(2, '0')
}

///|
fn pad4(value : Int) -> String {
  value.to_string().pad_start(4, '0')
}
