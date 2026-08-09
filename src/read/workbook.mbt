///|
/// The workbook-level keys, read onto an already-built workbook.
fn read_workbook_keys(
  backend : @xlsx.Workbook,
  workbook : @model.Workbook,
  notes : Notes,
) -> Unit {
  read_defined_names(backend, workbook, slicer_caches(backend), notes)
  read_properties(backend, workbook, notes)
  read_calc(backend, workbook, notes)
}

///|
/// The workbook's default font face. Excel's own default is Calibri, and every
/// file it writes records one, so saying it back would put a key on every
/// extracted spec that changes nothing.
fn read_default_font(backend : @xlsx.Workbook) -> String? {
  let name = backend.get_default_font()
  if name.is_empty() || name == EXCEL_DEFAULT_FONT {
    None
  } else {
    Some(name)
  }
}

///|
/// The font Excel uses when a workbook names none.
const EXCEL_DEFAULT_FONT : String = "Calibri"

///|
/// Named definitions (ADR-013), as `defs.values` and `defs.formulas`.
///
/// Excel keeps its own bookkeeping in the same table — the print area and the
/// repeated titles are defined names beginning `_xlnm.` — and those are Excel's
/// to write, not the spec's. A name scoped to one sheet is skipped too: the
/// schema's definitions are workbook-wide, and recovering a sheet-scoped one as
/// a workbook-wide one would change which cells it resolves for.
///
/// `slicer_caches` names the other bookkeeping kind: a slicer's cache is a
/// defined name the backend writes for it, so recovering it *and* the slicer
/// would make the spec ask for the same name twice and refuse to compile.
fn read_defined_names(
  backend : @xlsx.Workbook,
  workbook : @model.Workbook,
  slicer_caches : @set.Set[String],
  notes : Notes,
) -> Unit {
  for defined in backend.get_defined_names() {
    if defined.name.has_prefix(EXCEL_RESERVED_NAME_PREFIX) {
      continue
    }
    if slicer_caches.contains(defined.name) {
      continue
    }
    // A workbook-wide name is scoped `Workbook`, not to nothing; a name scoped
    // to a sheet resolves only there, and recovering it workbook-wide would
    // change which cells it means.
    if !(defined.scope.is_empty() || defined.scope == WORKBOOK_SCOPE) {
      notes.drop(
        "a name defined for one sheet only, which the spec declares workbook-wide",
      )
      continue
    }
    workbook.add_defined_name(defined.name, defined_value(defined.refers_to))
  }
}

///|
/// The prefix Excel puts on the defined names it owns (ECMA-376 §18.2.6).
const EXCEL_RESERVED_NAME_PREFIX : String = "_xlnm."

///|
/// What the backend calls a name that belongs to the whole workbook rather than
/// to one sheet.
const WORKBOOK_SCOPE : String = "Workbook"

///|
/// What a defined name refers to, read from the formula literal it is stored as
/// — the inverse of the emitter's `refers_to`. A quoted string is text (Excel
/// doubles an inner quote), `TRUE`/`FALSE` a boolean, a bare number a number,
/// and anything else a formula, which is what a reference to cells is.
fn defined_value(refers_to : String) -> @model.CellValue {
  if refers_to.has_prefix("\"") &&
    refers_to.has_suffix("\"") &&
    refers_to.length() >= 2 {
    return Text(
      refers_to[1:refers_to.length() - 1]
      .to_owned()
      .replace_all(old="\"\"", new="\""),
    )
  }
  match refers_to {
    "TRUE" => return Bool(true)
    "FALSE" => return Bool(false)
    _ => ()
  }
  Number(@string.parse_double(refers_to)) catch {
    // A formula is stored with a leading `=` in the file and without one in the
    // spec, which strips it on the way in either way.
    _ =>
      Formula(
        formula=if refers_to.has_prefix("=") {
          refers_to[1:].to_owned()
        } else {
          refers_to
        },
        cached=None,
      )
  }
}

///|
/// The document properties, and the custom ones beside them.
fn read_properties(
  backend : @xlsx.Workbook,
  workbook : @model.Workbook,
  notes : Notes,
) -> Unit {
  let core = backend.get_doc_props()
  let app = backend.get_app_props()
  let custom = []
  for property in backend.get_custom_props() {
    match property.value {
      Some(Integer(number)) =>
        custom.push(
          (
            { name: property.name, value: Number(number.to_double()) } :
            @model.CustomProperty),
        )
      Some(Float(number)) =>
        custom.push({ name: property.name, value: Number(number) })
      Some(Boolean(flag)) =>
        custom.push({ name: property.name, value: Bool(flag) })
      Some(Text(text)) =>
        custom.push({ name: property.name, value: Text(text) })
      Some(DateTime(text)) => {
        // The schema has no date property: Excel wants a full timestamp with a
        // zone, and the spec says to write one as text until that is settled.
        notes.drop("a date document property, kept as its text")
        custom.push({ name: property.name, value: Text(text) })
      }
      None => ()
    }
  }
  let properties : @model.DocumentProperties = {
    title: non_empty(core.title),
    subject: non_empty(core.subject),
    author: authored_by(core.creator),
    keywords: non_empty(core.keywords),
    description: non_empty(core.description),
    category: non_empty(core.category),
    status: non_empty(core.content_status),
    language: non_empty(core.language),
    version: non_empty(core.version),
    company: non_empty(app.company),
    custom,
  }
  if properties != @model.DocumentProperties::empty() {
    workbook.set_properties(properties)
  }
}

///|
/// How Excel recalculates on open. Only the two settings the schema names are
/// read; the rest of Excel's calculation chain is its own bookkeeping.
fn read_calc(
  backend : @xlsx.Workbook,
  workbook : @model.Workbook,
  notes : Notes,
) -> Unit {
  let props = backend.get_calc_props()
  let mode : @model.CalcMode? = match props.calc_mode {
    Some("manual") => Some(Manual)
    Some("autoNoTable") => Some(AutomaticNoTables)
    // `auto` is Excel's default, and writing it down says nothing.
    _ => None
  }
  if props.iterate is Some(true) {
    notes.drop("iterative calculation, which the spec does not set")
  }
  let on_load = if props.full_calc_on_load is Some(true) {
    Some(true)
  } else {
    None
  }
  let calc : @model.CalcSettings = { mode, on_load }
  if calc != ({ mode: None, on_load: None } : @model.CalcSettings) {
    workbook.set_calc(calc)
  }
}

///|
/// The author, unless it is the writing library signing its own work. Every file
/// the backend produces is stamped `mbtexcel` as its creator, so keeping that
/// would put a name on every extracted spec that names nobody who wrote it.
fn authored_by(creator : String) -> String? {
  if creator == BACKEND_SIGNATURE {
    None
  } else {
    non_empty(creator)
  }
}

///|
/// What the Excel backend writes as the creator of a file it produced.
const BACKEND_SIGNATURE : String = "mbtexcel"

///|
/// Text, unless it is empty — the backend returns `""` for a property the file
/// never set, and the schema tells "not said" from "said to be blank".
fn non_empty(text : String) -> String? {
  if text.is_empty() {
    None
  } else {
    Some(text)
  }
}

///|
/// A sheet's protection, as Excel's "Protect Sheet" dialog records it.
///
/// The password is deliberately **not** recovered: the file keeps a hash, not
/// the word, so there is nothing to write down — and a spec that silently lost
/// it would look protected while opening to anyone.
fn read_sheet_protection(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit raise {
  // The presence of the record is the signal: an unprotected sheet has none,
  // and `get_sheet_protection` fills in defaults whether or not there is one.
  guard backend.sheet(sheet.name) is Some(source) &&
    source.sheet_protection is Some(_) else {
    return
  }
  let protection = backend.get_sheet_protection(sheet.name)
  if !protection.password.is_empty() {
    notes.drop(
      "a sheet-protection password, which the file keeps only as a hash — set it again if it mattered",
    )
  }
  sheet.set_protection({
    password: None,
    select_locked_cells: protection.select_locked_cells,
    select_unlocked_cells: protection.select_unlocked_cells,
    format_cells: protection.format_cells,
    format_columns: protection.format_columns,
    format_rows: protection.format_rows,
    insert_columns: protection.insert_columns,
    insert_rows: protection.insert_rows,
    insert_hyperlinks: protection.insert_hyperlinks,
    delete_columns: protection.delete_columns,
    delete_rows: protection.delete_rows,
    sort: protection.sort,
    auto_filter: protection.auto_filter,
    pivot_tables: protection.pivot_tables,
    edit_objects: protection.edit_objects,
    edit_scenarios: protection.edit_scenarios,
  })
}
