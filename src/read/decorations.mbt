///|
/// Everything layered over a sheet's cells.
fn read_decorations(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  dates : @units.DateSystem,
  notes : Notes,
) -> Unit raise {
  read_comments(backend, sheet)
  read_conditional_formats(backend, sheet, dates, notes)
  read_links(backend, sheet, notes)
  read_validations(backend, sheet, dates, notes)
  read_tables(backend, sheet, notes)
  read_filter(backend, sheet, notes)
}

///|
/// Cell notes. The backend keeps the runs a note was typed in; the schema keeps
/// the text, since a note's own formatting is not something a spec can set.
fn read_comments(backend : @xlsx.Workbook, sheet : @model.Sheet) -> Unit raise {
  for comment in backend.get_comments(sheet.name) {
    guard @units.CellRef::parse_a1(comment.cell) is Some(at) else { continue }
    let author = if comment.author.is_empty() {
      None
    } else {
      Some(comment.author)
    }
    sheet.add_comment(at, comment.text, author?)
  }
}

///|
/// Hyperlinks, both kinds. The backend lists the linked cells and then answers
/// per cell, so the two calls together are what a `links:` block holds.
fn read_links(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit raise {
  for reference in backend.get_hyperlink_cells(sheet.name) {
    guard backend.get_cell_hyperlink(sheet.name, reference) is Some(link) else {
      continue
    }
    guard @units.CellRef::parse_a1(reference) is Some(at) else { continue }
    let target : @model.LinkTarget? = match link.link_type {
      External => Some(Url(link.target))
      Location =>
        match link.location {
          Some(location) => Some(Location(location))
          None => Some(Location(link.target))
        }
      Unset => None
    }
    guard target is Some(target) else { continue }
    if link.display is Some(display) && !display.is_empty() {
      // Excel's "text to display" overwrites the cell's own value rather than
      // decorating it, which is not what a `links:` entry does.
      notes.drop(
        "a hyperlink's display text, which a link does not set — the cell's own value is what shows",
      )
    }
    sheet.add_link(at, target, tip?=link.tooltip)
  }
}

///|
/// Data validations. The file spells the rule as a type, an operator, and up to
/// two formulas; the schema spells it as a rule with its bounds inside.
fn read_validations(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  dates : @units.DateSystem,
  notes : Notes,
) -> Unit raise {
  for validation in backend.get_data_validations(sheet.name) {
    // A validation may cover several disjoint regions in one record. The schema
    // gives each its own entry, which says the same thing.
    for reference in validation.sqref.split(" ") {
      guard @model.CellRange::parse_loose(reference.to_owned()) is Some(at) else {
        continue
      }
      guard read_validation_rule(validation, dates, notes) is Some(rule) else {
        continue
      }
      sheet.add_validation({
        at,
        rule,
        allow_blank: validation.allow_blank,
        prompt: read_prompt(validation),
        error: read_validation_error(validation),
      })
    }
  }
}

///|
/// The rule itself, or `None` where the schema has no way to say it.
fn read_validation_rule(
  validation : @xlsx.DataValidation,
  dates : @units.DateSystem,
  notes : Notes,
) -> @model.ValidationRule? {
  let first = validation.formula1
  match validation.validation_type {
    "list" => {
      // A literal drop-down is a quoted, comma-joined list; anything else is a
      // reference to the cells the choices live in.
      if first.has_prefix("\"") && first.has_suffix("\"") && first.length() >= 2 {
        let inner = first[1:first.length() - 1].to_owned()
        let choices = []
        for choice in inner.split(",") {
          choices.push(choice.to_owned())
        }
        return Some(List(choices))
      }
      match parse_sheet_range(first) {
        Some(range) => Some(ListFrom(range))
        None => {
          notes.drop("a drop-down whose source '\{first}' is not a plain range")
          None
        }
      }
    }
    kind => {
      guard validation_kind(kind) is Some(kind_value) else {
        notes.drop("a '\{kind}' validation, which the spec has no rule for")
        return None
      }
      guard read_comparison(validation, kind_value, dates) is Some(check) else {
        notes.drop(
          "a validation comparing with '\{validation.operator}', which the spec has no name for",
        )
        return None
      }
      Some(Compare(kind=kind_value, check~))
    }
  }
}

///|
fn validation_kind(kind : String) -> @model.ValidationKind? {
  match kind {
    "whole" => Some(Whole)
    "decimal" => Some(Decimal)
    "textLength" => Some(TextLength)
    "date" => Some(DateValue)
    _ => None
  }
}

///|
/// The comparison, with its bounds read as the kind expects them.
fn read_comparison(
  validation : @xlsx.DataValidation,
  kind : @model.ValidationKind,
  dates : @units.DateSystem,
) -> @model.Comparison? {
  guard read_bound(validation.formula1, kind, dates) is Some(first) else {
    return None
  }
  let second = read_bound(validation.formula2, kind, dates)
  match (validation.operator, second) {
    ("between", Some(second)) => Some(Between(first, second))
    ("notBetween", Some(second)) => Some(NotBetween(first, second))
    ("equal", _) => Some(Equal(first))
    ("notEqual", _) => Some(NotEqual(first))
    ("greaterThanOrEqual", _) => Some(AtLeast(first))
    ("lessThanOrEqual", _) => Some(AtMost(first))
    ("greaterThan", _) => Some(GreaterThan(first))
    ("lessThan", _) => Some(LessThan(first))
    _ => None
  }
}

///|
/// One endpoint, read as the kind expects it.
fn read_bound(
  formula : String,
  kind : @model.ValidationKind,
  dates : @units.DateSystem,
) -> @model.Bound? {
  guard !formula.is_empty() else { return None }
  let number = @string.parse_double(formula) catch { _ => return None }
  match kind {
    // A date bound is a serial in the file and a written date in the spec, so
    // this is the one place the workbook's epoch matters to a validation.
    DateValue =>
      match @units.DateTime::from_serial(number, dates) {
        Some(datetime) => Some(Date(datetime))
        None => None
      }
    Whole | Decimal | TextLength => Some(Number(number))
  }
}

///|
/// The pop-up shown on selection, where the file carries one.
fn read_prompt(validation : @xlsx.DataValidation) -> @model.ValidationPrompt? {
  guard validation.show_input_message else { return None }
  let title = validation.prompt_title.unwrap_or("")
  let body = validation.prompt.unwrap_or("")
  if title.is_empty() && body.is_empty() {
    None
  } else {
    Some({ title, body, })
  }
}

///|
/// What Excel says about a rejected value.
fn read_validation_error(
  validation : @xlsx.DataValidation,
) -> @model.ValidationError? {
  guard validation.show_error_message else { return None }
  let title = validation.error_title.unwrap_or("")
  let body = validation.error.unwrap_or("")
  if title.is_empty() && body.is_empty() {
    return None
  }
  let style : @model.ValidationErrorStyle = match validation.error_style {
    Some("warning") => Warning
    Some("information") => Information
    _ => Stop
  }
  Some({ title, body, style, })
}

///|
/// Excel tables. The header row's cells are ordinary cells and come back with
/// the rest; what is recovered here is the declaration over them.
fn read_tables(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit raise {
  for table in backend.get_tables(sheet.name) {
    guard @model.CellRange::parse(table.range_ref) is Some(at) else {
      guard @model.CellRange::parse(table.range) is Some(at) else { continue }
      add_table(sheet, at, table, notes)
      continue
    }
    add_table(sheet, at, table, notes)
  }
}

///|
fn add_table(
  sheet : @model.Sheet,
  at : @model.CellRange,
  table : @xlsx.Table,
  notes : Notes,
) -> Unit {
  if !table.show_header_row {
    // The schema's tables always show their header row, because that is where
    // the column names come from.
    notes.drop(
      "a table with its header row hidden, which the spec always shows",
    )
  }
  sheet.add_table({
    at,
    name: if table.name.is_empty() {
      None
    } else {
      Some(table.name)
    },
    style: if table.style_name.is_empty() {
      None
    } else {
      Some(table.style_name)
    },
    banded_rows: table.show_row_stripes,
    banded_columns: table.show_column_stripes,
    first_column: table.show_first_column,
    last_column: table.show_last_column,
  })
}

///|
/// The sheet's auto filter. The schema names the range and leaves the criteria
/// to whoever opens the file, since a saved filter state is a view rather than
/// a description of the sheet.
fn read_filter(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  notes : Notes,
) -> Unit raise {
  guard backend.get_auto_filter(sheet.name) is Some(filter) else { return }
  guard @model.CellRange::parse(filter.range_ref) is Some(range) else { return }
  if !filter.columns.is_empty() {
    notes.drop(
      "a filter with criteria already applied, kept as the plain filter over its range",
    )
  }
  sheet.set_filter(range)
}

///|
/// A `Sheet!A1:B2` reference as the schema's sheet-qualified range.
fn parse_sheet_range(text : String) -> @model.SheetRange? {
  let bare = text.replace_all(old="$", new="").replace_all(old="'", new="")
  match bare.split_once("!") {
    Some((name, rest)) =>
      match @model.CellRange::parse_loose(rest.to_owned()) {
        Some(range) => Some({ sheet: Some(name.to_owned()), range, })
        None => None
      }
    None =>
      match @model.CellRange::parse_loose(bare) {
        Some(range) => Some({ sheet: None, range, })
        None => None
      }
  }
}
