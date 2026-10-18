///|
/// Add every populated cell in the used range, scanned by address since the
/// backend does not expose its cell list.
fn read_cells(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  styles : StyleTable,
  notes : Notes,
) -> Unit raise {
  guard used_range(backend, sheet.name) is Some(range) else { return }
  guard backend.sheet(sheet.name) is Some(source) else { return }
  let folded = fold_shared_formulas(
    backend, source, sheet, range, styles, notes,
  )
  for row in range.top_left.row..<=range.bottom_right.row {
    for col in range.top_left.col..<=range.bottom_right.col {
      let at = @units.CellRef(col~, row~)
      let reference = at.to_a1()
      // A cell a `formulas:` range already covers must not be written again:
      // the loader refuses a range that overlaps a `cells:` entry, so writing
      // both would produce a spec that does not compile.
      if folded.contains(reference) {
        continue
      }
      let value = read_value(backend, source, sheet.name, at, notes)
      let style = read_cell_style(backend, sheet.name, reference, styles, notes)
      match (value, style) {
        (Some(value), _) => sheet.set(at, value, style?)
        // A cell with a style and nothing in it — the shaded box, the ruled
        // table edge, the blank half of a merged heading. A real workbook has
        // these by the hundred thousand, and dropping them redrew it (#48).
        (None, Some(style)) => sheet.set(at, Blank, style~)
        (None, None) => ()
      }
    }
  }
}

///|
/// What one cell holds: a formula, rich text, or a plain value — in that order,
/// because a formula cell also carries a cached result and rich text also reads
/// back as its concatenation.
fn read_value(
  backend : @xlsx.Workbook,
  source : @xlsx.Worksheet,
  sheet_name : String,
  at : @units.CellRef,
  notes : Notes,
) -> @model.CellValue? raise {
  let reference = at.to_a1()
  if backend.get_cell_formula(sheet_name, reference) is Some(formula) &&
    !formula.is_empty() {
    // The cached result is left behind: Excel recomputes it on open, so
    // carrying it would put a stale number in the spec that reads like an
    // assertion about the formula's answer.
    return Some(Formula(formula=@model.from_file_formula(formula), cached=None))
  }
  // A shared formula's followers store no text, only the master they follow;
  // leaving them out turned a calculation into its stale cached number (#52).
  if shared_follower_formula(source, at, notes) is Some(formula) {
    return Some(Formula(formula=@model.from_file_formula(formula), cached=None))
  }
  // The backend reports every shared string as rich text, a plain one as a
  // single run; only a cell that really mixes fonts needs `rich:`.
  if backend.get_cell_rich_text(sheet_name, reference) is Some(runs) &&
    is_mixed(runs) {
    return Some(RichText(runs.map(run => read_run(backend, run, notes))))
  }
  read_scalar(backend, sheet_name, reference)
}

///|
/// Whether a run list says anything a plain string could not: more than one
/// run, or one that carries a font of its own.
fn is_mixed(runs : Array[@xlsx.RichTextRun]) -> Bool {
  runs.length() > 1 || (runs.length() == 1 && runs[0].font is Some(_))
}

///|
/// A cell's stored value. A number under a date format stays a number: it
/// compiles back identically, and `type: date` would be a guess (ADR-017).
fn read_scalar(
  backend : @xlsx.Workbook,
  sheet_name : String,
  reference : String,
) -> @model.CellValue? raise {
  match backend.get_cell_value_raw(sheet_name, reference) {
    // The backend fills a shared formula's follower cells with an empty string
    // rather than leaving them out, so an empty one is nothing to recover.
    Some(String("")) => None
    Some(String(text)) => Some(Text(text))
    Some(Numeric(number)) => Some(Number(number))
    Some(Bool(flag)) => Some(Bool(flag))
    Some(Error(text)) => Some(Error(text))
    None => None
  }
}

///|
/// One run of rich text. The run's font is narrower here than in the file — see
/// `read_font` for what the schema cannot say.
fn read_run(
  backend : @xlsx.Workbook,
  run : @xlsx.RichTextRun,
  notes : Notes,
) -> @model.RichRun {
  let font : @model.Font? = match run.font {
    Some(font) =>
      Some({
        bold: some_true(font.bold),
        italic: some_true(font.italic),
        underline: read_underline(font.underline, notes),
        strike: some_true(font.strike),
        size: font.size,
        name: font.family,
        // A run's font carries the theme and palette indices a cell's font
        // does, and resolves them the same way: a run left out of that would
        // lose its colour where the cell beside it kept one.
        color: resolve_color(
          backend,
          font.color,
          theme=font.color_theme,
          indexed=font.color_indexed,
          tint=font.color_tint,
          what="a rich-text run's",
          notes~,
        ),
      })
    None => None
  }
  { text: run.text, font, }
}

///|
/// A rich-text run's flags are plain booleans rather than options; `false` is
/// the default and saying so in the spec would be noise.
fn some_true(flag : Bool) -> Bool? {
  if flag {
    Some(true)
  } else {
    None
  }
}
