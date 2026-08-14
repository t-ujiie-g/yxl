///|
/// The top-level mapping key that holds the deliberate one-off deviations.
const OVERRIDES_KEY : String = "overrides"

///|
/// The top-level `overrides:` sequence (ADR-018).
fn load_overrides(
  node : @yaml.Node,
  workbook : @model.Workbook,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'\{OVERRIDES_KEY}'") {
    workbook.add_override(load_override(item, file~, defs~))
  }
}

///|
/// One `overrides:` entry: `at:` naming a single cell on a named sheet, the
/// facets it replaces — the same `value` / `formula` / `rich` / `type` /
/// `format` / `style` a `cells:` entry writes — and an optional `reason:`.
fn load_override(
  node : @yaml.Node,
  file~ : String,
  defs~ : Defs,
) -> @model.Override raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="an override")
  let text = expect_string(
    required_at(entries, file~, subject="an override"),
    file~,
    context="override 'at'",
  )
  let (sheet, reference) = split_sheet_prefix(text, file~, what="override 'at'")
  guard sheet is Some(sheet) else {
    raise schema_error(
      file~,
      "override 'at' must name the sheet it lands on: '\{text}' (write 'Sheet!\{text}')",
    )
  }
  guard !reference.contains(":") else {
    raise schema_error(
      file~,
      "override 'at' takes a single cell, not the range '\{text}'; write one entry per cell",
    )
  }
  let at = expect_cell_ref(reference, file~, what="override 'at'")
  let mut reason = None
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => ()
      "reason" =>
        reason = Some(
          expect_string(value, file~, context="override '\{text}' reason"),
        )
      "value" | "formula" | "rich" | "type" | "format" | "style" => ()
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in override '\{text}' (expected 'at', 'reason', 'value', 'formula', 'rich', 'type', 'format', or 'style')",
        )
    }
  }
  let writes_value = ["value", "formula", "rich"]
    .iter()
    .any(key => find_key(entries, key) is Some(_))
  let writes_style = find_key(entries, "style") is Some(_) ||
    find_key(entries, "format") is Some(_)
  guard writes_value || writes_style else {
    raise schema_error(
      file~,
      "override '\{text}' changes nothing (expected a 'value', a 'formula', a 'rich', a 'style', or a 'format')",
    )
  }
  // The facets are the cell grammar; `at` and `reason` are the override's own,
  // and would be unknown keys to it.
  let (value, style) = load_expanded_cell(
    entries.filter(entry => entry.0 != "at" && entry.0 != "reason"),
    file~,
    reference=text,
    defs~,
  )
  {
    sheet,
    at,
    // A style-only override leaves the value alone, and the cell grammar's
    // stand-in for "no value given" is `Blank` — which here means the facet is
    // absent, not that the cell is to be emptied.
    value: if writes_value {
      Some(value)
    } else {
      None
    },
    style,
    reason,
  }
}

///|
/// What an override may and may not land on, checked once every sheet is loaded
/// (ADR-018): a declared sheet, one entry per cell, and something to deviate
/// from.
///
/// A `formulas:` range compiles to a shared formula stored at the range's
/// top-left cell (ECMA-376 §18.3.1.40), so overriding *that* cell would leave
/// the rest of the range following a formula that is no longer there. Every
/// other cell of the range may be overridden.
fn check_overrides(
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for index, entry in workbook.overrides {
    let at = "\{entry.sheet}!\{entry.at.to_a1()}"
    guard workbook.sheet(entry.sheet) is Some(sheet) else {
      raise schema_error(
        file~,
        "override '\{at}' names sheet '\{entry.sheet}', which is not declared",
      )
    }
    for earlier in workbook.overrides[:index] {
      guard !(earlier.sheet == entry.sheet && earlier.at == entry.at) else {
        raise schema_error(
          file~,
          "override '\{at}' is declared twice; one cell has one override",
        )
      }
    }
    let filled = sheet.formulas
      .iter()
      .find_first(range => within(entry.at, range.at))
    if filled is Some(range) && range.at.top_left == entry.at {
      raise schema_error(
        file~,
        "override '\{at}' is the anchor of formula range '\{range.at.to_a1()}', where the shared formula is stored; override another cell of the range, or start the range below it",
      )
    }
    guard filled is Some(_) ||
      sheet.cells.iter().any(cell => cell.pos == entry.at) else {
      raise schema_error(
        file~,
        "override '\{at}' has nothing to override: no 'cells', 'data', or 'formulas' entry writes that cell — write it as a 'cells' entry instead",
      )
    }
  }
}
