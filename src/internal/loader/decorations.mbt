///|
/// A sheet's `filter:` — a range or a layout, or `{ at, columns }` with saved
/// criteria (`docs/spec.md` §10). A repeated key is a parse error, so one per
/// sheet.
fn load_filter(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  let columns_of : Map[String, Int32] = Map([])
  let filter_range = text => {
    match layout_here(text, defs~, sheet=sheet.name, file~, what="filter") {
      Some(layout) => {
        for column in layout.columns {
          columns_of[column.0] = column.1
        }
        table_range(layout)
      }
      None => parse_range(text, file~, what="filter range")
    }
  }
  guard node is @yaml.Map(entries) else {
    let text = expect_string(node, file~, context="sheet 'filter'")
    sheet.set_filter(filter_range(text))
    return
  }
  let mut range = None
  let mut columns = []
  for entry in entries {
    match entry {
      ("at", value) => {
        let text = expect_string(value, file~, context="filter 'at'")
        range = Some(filter_range(text))
      }
      ("columns", value) =>
        columns = expect_seq(value, file~, context="filter 'columns'")
      (key, _) =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in filter (expected 'at' or 'columns')",
        )
    }
  }
  guard range is Some(range) else {
    raise schema_error(file~, "filter needs 'at', the range it covers")
  }
  let loaded : Array[@model.FilterColumn] = []
  for column in columns {
    let (filter_column, letters) = load_filter_column(
      column,
      range,
      columns_of,
      file~,
    )
    if loaded.iter().any(earlier => earlier.column == filter_column.column) {
      raise schema_error(
        file~,
        "filter column '\{letters}' is given twice; Excel keeps one criterion per column",
      )
    }
    loaded.push(filter_column)
  }
  sheet.set_filter(range, columns=loaded)
}

///|
/// One `filter.columns` entry: `at:` and either `values:` or one comparison.
/// Over a layout, `at:` may name one of its columns.
fn load_filter_column(
  node : @yaml.Node,
  range : @model.CellRange,
  columns_of : Map[String, Int32],
  file~ : String,
) -> (@model.FilterColumn, String) raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="filter column")
  let mut column = None
  let criteria = []
  for entry in entries {
    if entry is ("at", value) {
      let text = expect_string(value, file~, context="filter column 'at'")
      let found = match columns_of.get(text) {
        Some(col) => Some(col)
        None => @units.parse_column(text)
      }
      guard found is Some(index) else {
        raise schema_error(
          file~,
          "filter column 'at' must be a column letter, got '\{text}'",
        )
      }
      guard index >= range.top_left.col && index <= range.bottom_right.col else {
        raise schema_error(
          file~,
          "filter column '\{text}' is outside the filter's range '\{range.to_a1()}'",
        )
      }
      column = Some((index, text))
    } else {
      criteria.push(entry)
    }
  }
  guard column is Some((index, letters)) else {
    raise schema_error(file~, "filter column needs 'at', the column it filters")
  }
  let context = "filter column '\{letters}'"
  guard criteria is [(key, value)] else {
    raise schema_error(
      file~,
      "\{context} takes exactly one criterion: 'values' or a comparison (\{COMPARISONS})",
    )
  }
  let criterion : @model.FilterCriterion = match key {
    "values" => Values(load_filter_values(value, file~, context~))
    "top" | "bottom" | "dynamic" | "color" | "icon" =>
      raise schema_error(
        file~,
        "\{context} asks for a '\{key}' filter, which the Excel backend cannot write; use 'values' or a comparison",
      )
    _ =>
      Compare(
        load_comparison(
          @yaml.Map(criteria),
          file~,
          read_bound=(node, what) => infer_bound(node, file~, what~),
          context~,
        ),
      )
  }
  ({ column: index, criterion, }, letters)
}

///|
/// A checkbox list: the values as cells display them, so text or whole numbers.
fn load_filter_values(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Array[String] raise @diag.SchemaError {
  let items = expect_seq(node, file~, context="\{context} 'values'")
  guard !items.is_empty() else {
    raise schema_error(file~, "\{context} 'values' is empty; list at least one")
  }
  items.map(item => {
    match item {
      @yaml.Str(text) => text
      @yaml.Int(number) => number.to_string()
      _ =>
        raise schema_error(
          file~,
          "\{context} 'values' holds text or whole numbers, as the cells display them",
        )
    }
  })
}

///|
/// A sheet's `links:` — a mapping of cell reference to link. The value is either
/// a URL on its own or a mapping naming the target and a tooltip.
fn load_links(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  for entry in by_cell(node, sheet, file~, defs~, what="link") {
    let (cell, reference, value) = entry
    let (target, tip) = load_link(value, file~, reference~)
    sheet.add_link(cell, target, tip?)
  }
}

///|
/// A `links:` or `comments:` block as (cell, its name in diagnostics, entry): a
/// mapping keyed by A1, or a list whose entries carry their own `at:`, an A1
/// cell or a cell of a named layout on this sheet.
fn by_cell(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
  what~ : String,
) -> Array[(@units.CellRef, String, @yaml.Node)] raise @diag.SchemaError {
  guard node is @yaml.Seq(items) else {
    return expect_map(node, file~, context="'\{what}s'").map(entry => {
      let (reference, value) = entry
      (expect_cell_ref(reference, file~, what="'\{what}s'"), reference, value)
    })
  }
  items.map(item => {
    let entries = expect_map(item, file~, context="a \{what}")
    let cell = match required_at(entries, file~, subject="a \{what}") {
      @yaml.Map(target) => {
        let (on, cell) = resolve_layout_cell(
          target,
          defs~,
          file~,
          what="\{what} 'at'",
        )
        guard on == sheet.name else {
          raise schema_error(
            file~,
            "\{what} 'at' names a layout on sheet '\{on}', not this one",
          )
        }
        cell
      }
      at =>
        expect_cell_ref(
          expect_string(at, file~, context="\{what} 'at'"),
          file~,
          what="\{what} 'at'",
        )
    }
    let rest = entries.filter(entry => entry.0 != "at")
    (cell, cell.to_a1(), @yaml.Map(rest))
  })
}

///|
/// One `links:` entry. A bare string is a URL — the common case, and the one
/// worth writing in one line; an in-workbook target needs the explicit `to:`,
/// since `Summary!A1` and a URL are not distinguishable by shape alone.
fn load_link(
  node : @yaml.Node,
  file~ : String,
  reference~ : String,
) -> (@model.LinkTarget, String?) raise @diag.SchemaError {
  let context = "link '\{reference}'"
  if node is @yaml.Str(url) {
    return (Url(url), None)
  }
  let mut target : @model.LinkTarget? = None
  let mut tip : String? = None
  for entry in expect_map(node, file~, context~) {
    let (key, value) = entry
    match key {
      "url" =>
        target = Some(
          Url(expect_string(value, file~, context="\{context} 'url'")),
        )
      "to" =>
        target = Some(
          Location(
            canonical_location(
              expect_string(value, file~, context="\{context} 'to'"),
            ),
          ),
        )
      "tip" =>
        tip = Some(expect_string(value, file~, context="\{context} 'tip'"))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'url', 'to', or 'tip')",
        )
    }
  }
  guard target is Some(target) else {
    raise schema_error(
      file~,
      "\{context} needs 'url' (outside the workbook) or 'to' (inside it)",
    )
  }
  (target, tip)
}

///|
/// A sheet's `comments:` — a mapping of cell reference to note. The value is
/// either the text on its own or a mapping naming the author too.
fn load_comments(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
  defs~ : Defs,
) -> Unit raise @diag.SchemaError {
  for entry in by_cell(node, sheet, file~, defs~, what="comment") {
    let (cell, reference, value) = entry
    let context = "comment '\{reference}'"
    if value is @yaml.Str(text) {
      sheet.add_comment(cell, text)
      continue
    }
    let mut text = None
    let mut author = None
    for inner in expect_map(value, file~, context~) {
      let (key, value) = inner
      match key {
        "text" =>
          text = Some(expect_string(value, file~, context="\{context} 'text'"))
        "author" =>
          author = Some(
            expect_string(value, file~, context="\{context} 'author'"),
          )
        _ =>
          raise schema_error(
            file~,
            "unknown key '\{key}' in \{context} (expected 'text' or 'author')",
          )
      }
    }
    guard text is Some(text) else {
      raise schema_error(file~, "\{context} is missing required key 'text'")
    }
    sheet.add_comment(cell, text, author?)
  }
}

///|
/// A comparison: exactly one operator key and its bound(s), shared by validations
/// and conditional formats; `read_bound` is the part that differs.
fn load_comparison(
  node : @yaml.Node,
  file~ : String,
  read_bound~ : (@yaml.Node, String) -> @model.Bound raise @diag.SchemaError,
  context~ : String,
) -> @model.Comparison raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="\{context} rule")
  guard entries.length() == 1 else {
    raise schema_error(
      file~,
      "\{context} rule takes exactly one comparison (\{COMPARISONS})",
    )
  }
  let (key, value) = entries[0]
  let what = "\{context} '\{key}'"
  let pair = () => {
    let items = expect_seq(value, file~, context=what)
    guard items.length() == 2 else {
      raise schema_error(file~, "\{what} takes exactly two bounds, [low, high]")
    }
    (read_bound(items[0], what), read_bound(items[1], what))
  }
  match key {
    "between" => {
      let (low, high) = pair()
      Between(low, high)
    }
    "not_between" => {
      let (low, high) = pair()
      NotBetween(low, high)
    }
    "equals" => Equal(read_bound(value, what))
    "not_equals" => NotEqual(read_bound(value, what))
    "at_least" => AtLeast(read_bound(value, what))
    "at_most" => AtMost(read_bound(value, what))
    "greater_than" => GreaterThan(read_bound(value, what))
    "less_than" => LessThan(read_bound(value, what))
    _ =>
      raise schema_error(
        file~,
        "unknown comparison '\{key}' in \{context} (expected \{COMPARISONS})",
      )
  }
}

///|
const COMPARISONS : String = "'between', 'not_between', 'equals', 'not_equals', 'at_least', 'at_most', 'greater_than', or 'less_than'"

///|
/// Every decoration naming another sheet must name a declared one. Run after the
/// whole spec loads, since a lookup sheet is often the last tab (ADR-006).
fn check_cross_sheet_references(
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  fn declared(name : String) -> Bool {
    workbook.sheet(name) is Some(_)
  }

  for sheet in workbook.sheets {
    for validation in sheet.validations {
      if validation.rule is ListFrom({ sheet: Some(source), .. }) &&
        !declared(source) {
        raise schema_error(
          file~,
          "validation on sheet '\{sheet.name}' sources its list from sheet '\{source}', which is not declared",
        )
      }
    }
    for chart in sheet.charts {
      for series in chart.series {
        // A chart plotting a sheet that does not exist opens as an empty frame,
        // saying nothing about which reference went nowhere.
        for source in [Some(series.values), series.categories] {
          guard source is Some({ sheet: Some(named), .. }) else { continue }
          guard declared(named) else {
            raise schema_error(
              file~,
              "chart at '\{chart.at.to_a1()}' on sheet '\{sheet.name}' plots sheet '\{named}', which is not declared",
            )
          }
        }
        guard series.name is Some(FromCell(sheet=Some(named), ..)) else {
          continue
        }
        guard declared(named) else {
          raise schema_error(
            file~,
            "chart at '\{chart.at.to_a1()}' on sheet '\{sheet.name}' names a series from sheet '\{named}', which is not declared",
          )
        }
      }
    }
    for group in sheet.sparklines {
      for cell in group.cells {
        // A sparkline over a missing sheet draws an empty cell, saying
        // nothing about which reference went nowhere.
        guard cell.data.sheet is Some(named) else { continue }
        guard declared(named) else {
          raise schema_error(
            file~,
            "sparkline at '\{cell.at.to_a1()}' on sheet '\{sheet.name}' plots sheet '\{named}', which is not declared",
          )
        }
      }
    }
    for link in sheet.links {
      guard link.target is Location(location) else { continue }
      // Only a sheet-qualified location can be checked; a bare one is a defined
      // name, which the spec may not be the thing that declares.
      guard location_sheet(location) is Some(target) else { continue }
      guard declared(target) else {
        raise schema_error(
          file~,
          "link at '\{link.at.to_a1()}' on sheet '\{sheet.name}' points at sheet '\{target}', which is not declared",
        )
      }
    }
  }
}

///|
/// A link's in-workbook target with its sheet quoted, always, as `quoted_sheet`
/// does: Excel rejects an unquoted `Q1 Sales!B2`. A defined name or malformed
/// quoting is left as written.
fn canonical_location(location : String) -> String {
  let (sheet, rest) = split_sheet_prefix(location, file="", what="") catch {
    _ => return location
  }
  match sheet {
    Some(name) => "'" + name.replace_all(old="'", new="''") + "'!" + rest
    None => location
  }
}

///|
/// The sheet a link location names, or `None` when it names none (a defined
/// name). Shares its quoting rules with `split_sheet_prefix`.
fn location_sheet(location : String) -> String? {
  // An unterminated quote is not a sheet reference; leave it to Excel rather
  // than reporting a confusing diagnostic about a link that may be a name.
  let (sheet, _) = split_sheet_prefix(location, file="", what="") catch {
    _ => return None
  }
  sheet
}

///|
/// Parse a possibly sheet-qualified range: `A1:B9`, `Lists!A1:A9`, or
/// `'Q3 data'!A1:A9`. A sheet name is quoted exactly when Excel would quote it,
/// and a `''` inside quotes is one literal quote.
fn parse_sheet_range(
  text : String,
  file~ : String,
  what~ : String,
  defs~ : Defs,
) -> @model.SheetRange raise @diag.SchemaError {
  if layout_range(text, defs) is Some(range) {
    return range
  }
  if !text.contains(":") && !text.contains("!") && !defs.layouts.is_empty() {
    let known = defs.layouts.keys().map(name => "'\{name}'").collect()
    raise schema_error(
      file~,
      "\{what} '\{text}' is neither a range nor a named layout or one of its columns (layouts: \{or_list(known)})",
    )
  }
  let (sheet, rest) = split_sheet_prefix(text, file~, what~)
  { sheet, range: parse_range(rest, file~, what~), }
}

///|
/// `@model.split_sheet_prefix` with an unterminated quote turned into a
/// diagnostic.
fn split_sheet_prefix(
  text : String,
  file~ : String,
  what~ : String,
) -> (String?, String) raise @diag.SchemaError {
  guard @model.split_sheet_prefix(text) is Some(split) else {
    raise schema_error(
      file~,
      "\{what} '\{text}' has an unterminated quoted sheet name (expected \"'Sheet name'!A1:B9\")",
    )
  }
  split
}
