// Recovering a sheet's cells: what each holds, and the style it wears.

///|
/// Walk the sheet's used range and add every populated cell to the model.
///
/// The scan is by address rather than by iterating the backend's own cell list,
/// which it does not expose; each lookup is O(1) through its index, so the cost
/// is the size of the rectangle rather than of the file.
fn read_cells(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  styles : StyleTable,
  notes : Notes,
) -> Unit raise {
  guard used_range(backend, sheet.name) is Some(range) else { return }
  let source = backend.sheet(sheet.name)
  let folded = fold_shared_formulas(
    backend, source, sheet, range, styles, notes,
  )
  for row in range.top_left.row..<=range.bottom_right.row {
    for col in range.top_left.col..<=range.bottom_right.col {
      let at = @units.CellRef::new(col~, row~)
      let reference = at.to_a1()
      // A cell a `formulas:` range already covers must not be written again:
      // the loader refuses a range that overlaps a `cells:` entry, so writing
      // both would produce a spec that does not compile.
      if folded.get(reference) is Some(_) {
        continue
      }
      let value = read_value(backend, source, sheet.name, at, notes)
      let style = read_cell_style(backend, sheet.name, reference, styles, notes)
      match (value, style) {
        (Some(value), _) => sheet.set(at, value, style?)
        // A cell with a style and nothing in it — the shaded box, the ruled
        // table edge, the blank half of a merged heading. It is written as a
        // blank cell wearing that style rather than left out: a real workbook
        // has these by the hundred thousand, and dropping them redrew it.
        (None, Some(style)) => sheet.set(at, Blank, style~)
        // A cell with neither is one the file never wrote.
        (None, None) => ()
      }
    }
  }
}

///|
/// The shared-formula masters whose whole range comes back as one `formulas:`
/// entry, as the set of cell addresses those ranges cover.
///
/// A shared formula is Excel's own form of the reuse ADR-004 asks for: the file
/// stores the text once against the range it governs and marks the rest of the
/// range as following it. Recovering that as the `formulas:` range it came from
/// keeps the sharing; recovering it cell by cell would emit N copies of
/// something the file declared once.
///
/// The fold is refused where a cell in the range wears a style, because a
/// `formulas:` range carries no styling (docs/spec.md §3) and there would be
/// nowhere to put it — those ranges come back as ordinary cells instead, each
/// with its own translated formula, which loses the sharing but nothing else.
fn fold_shared_formulas(
  backend : @xlsx.Workbook,
  source : @xlsx.Worksheet?,
  sheet : @model.Sheet,
  used : @model.CellRange,
  styles : StyleTable,
  notes : Notes,
) -> Map[String, Unit] raise {
  let covered : Map[String, Unit] = Map([])
  guard source is Some(source) else { return covered }
  for row in used.top_left.row..<=used.bottom_right.row {
    for col in used.top_left.col..<=used.bottom_right.col {
      guard source.get_cell_formula_info_rc(row, col) is Some(info) else {
        continue
      }
      // A master is the cell that holds the text *and* names the range; a
      // follower holds the index alone.
      guard info.shared_index is Some(index) &&
        info.range_ref is Some(reference) &&
        !info.formula.is_empty() else {
        continue
      }
      guard @model.CellRange::parse(reference) is Some(range) else { continue }
      if range_follows(source, backend, sheet.name, range, index, styles, notes) {
        sheet.add_formula({ at: range, formula: info.formula })
        for r in range.top_left.row..<=range.bottom_right.row {
          for c in range.top_left.col..<=range.bottom_right.col {
            covered[@units.CellRef::new(col=c, row=r).to_a1()] = ()
          }
        }
      }
    }
  }
  covered
}

///|
/// Whether every cell of `range` follows the shared formula `index` and carries
/// no style of its own — the two things a `formulas:` range needs to be true of
/// the region it replaces.
fn range_follows(
  source : @xlsx.Worksheet,
  backend : @xlsx.Workbook,
  sheet_name : String,
  range : @model.CellRange,
  index : UInt,
  styles : StyleTable,
  notes : Notes,
) -> Bool raise {
  for row in range.top_left.row..<=range.bottom_right.row {
    for col in range.top_left.col..<=range.bottom_right.col {
      guard source.get_cell_formula_info_rc(row, col) is Some(info) else {
        return false
      }
      guard info.shared_index is Some(other) && other == index else {
        return false
      }
      let reference = @units.CellRef::new(col~, row~).to_a1()
      if read_cell_style(backend, sheet_name, reference, styles, notes)
        is Some(_) {
        return false
      }
    }
  }
  true
}

///|
/// What one cell holds: a formula, rich text, or a plain value — in that order,
/// because a formula cell also carries a cached result and rich text also reads
/// back as its concatenation.
fn read_value(
  backend : @xlsx.Workbook,
  source : @xlsx.Worksheet?,
  sheet_name : String,
  at : @units.CellRef,
  notes : Notes,
) -> @model.CellValue? raise {
  let reference = at.to_a1()
  if backend.get_cell_formula(sheet_name, reference) is Some(formula) &&
    !formula.is_empty() {
    // The cached result is deliberately left behind. It is a display cache Excel
    // recomputes the moment the file opens, the backend hands it back as text
    // whatever it was, and carrying it would put a stale number in the spec that
    // reads like an assertion about the formula's answer.
    return Some(Formula(formula~, cached=None))
  }
  // A shared formula's followers store no text of their own: the file says only
  // which master they follow, and the formula is that master's with its relative
  // references shifted. Leaving them out turned a calculated cell into whatever
  // stale number was cached beside it (#52) — a spec that looks right and stops
  // recalculating.
  if shared_follower_formula(source, at, notes) is Some(formula) {
    return Some(Formula(formula~, cached=None))
  }
  // The backend answers `get_cell_rich_text` for *every* shared string, since a
  // plain one is a single run with no font. Recovering that as `rich:` would
  // turn every piece of text in the workbook into a three-line block saying
  // nothing; only a cell that genuinely mixes fonts needs the long form.
  if backend.get_cell_rich_text(sheet_name, reference) is Some(runs) &&
    is_mixed(runs) {
    return Some(RichText(runs.map(run => read_run(run, notes))))
  }
  read_scalar(backend, sheet_name, reference)
}

///|
/// The formula a shared-formula follower stands for, translated from its master
/// to this cell's position, or `None` where the cell follows nothing.
///
/// The translation is the backend's own — the same shifting Excel applies when
/// it opens the file — so `D3` under a master `B2*C2` at `D2` comes back as
/// `B3*C3`, and an absolute `$C$2` does not move.
fn shared_follower_formula(
  source : @xlsx.Worksheet?,
  at : @units.CellRef,
  notes : Notes,
) -> String? raise {
  guard source is Some(source) else { return None }
  guard source.get_cell_formula_info_rc(at.row, at.col) is Some(info) else {
    return None
  }
  guard info.formula.is_empty() && info.shared_index is Some(index) else {
    return None
  }
  guard source.shared_formula_master(index) is Some(master) else {
    notes.drop(
      "a cell following a shared formula whose master the file does not hold, which leaves nothing to translate",
    )
    return None
  }
  Some(master.translate_to(at.row, at.col))
}

///|
/// Whether a run list says anything a plain string could not: more than one run,
/// or one that carries a font of its own.
fn is_mixed(runs : Array[@xlsx.RichTextRun]) -> Bool {
  runs.length() > 1 || (runs.length() == 1 && runs[0].font is Some(_))
}

///|
/// A cell's stored value, with no formula or run structure around it.
///
/// A number is left a number even where a date format is over it. Turning it
/// into `type: date` would be a *guess* about what the author meant, and the
/// number plus its format compiles back to the identical cell — which is the
/// promise this whole direction makes (ADR-017). Someone who wants the date
/// spelling can write it; nothing is lost by not inventing it.
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
fn read_run(run : @xlsx.RichTextRun, notes : Notes) -> @model.RichRun {
  let font : @model.Font? = match run.font {
    Some(font) =>
      Some({
        bold: some_true(font.bold),
        italic: some_true(font.italic),
        underline: read_underline(font.underline, notes),
        strike: some_true(font.strike),
        size: font.size,
        name: font.family,
        color: read_color(font.color, notes),
      })
    None => None
  }
  { text: run.text, font }
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
