///|
/// How a value field is aggregated, as Excel's "Summarize Values By" menu names
/// each. One table serves both the lookup and the diagnostic.
let pivot_functions : Array[(String, @model.PivotFunction)] = [
  ("sum", Sum),
  ("count", Count),
  ("count_numbers", CountNumbers),
  ("average", Average),
  ("max", Max),
  ("min", Min),
  ("product", Product),
  ("std_dev", StdDev),
  ("std_dev_p", StdDevP),
  ("var", Var),
  ("var_p", VarP),
]

///|
/// A sheet's `pivots:` — a sequence of pivot tables, each placed at a range.
fn load_pivots(
  node : @yaml.Node,
  sheet : @model.Sheet,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for item in expect_seq(node, file~, context="'pivots'") {
    sheet.add_pivot(load_pivot(item, file~))
  }
}

///|
/// One `pivots:` entry: where it goes, what it summarizes, and how the fields
/// are laid out around it.
fn load_pivot(
  node : @yaml.Node,
  file~ : String,
) -> @model.Pivot raise @diag.SchemaError {
  let entries = expect_map(node, file~, context="a pivot table")
  let at = anchor_range(entries, file~, subject="a pivot table", noun="pivot")
  let context = "pivot '\{at.to_a1()}'"
  let mut source = None
  let mut rows : Array[@model.PivotField] = []
  let mut columns : Array[@model.PivotField] = []
  let mut filters : Array[@model.PivotField] = []
  let mut values : Array[@model.PivotValue] = []
  let mut name = None
  let mut style = None
  let mut row_grand_totals = true
  let mut column_grand_totals = true
  for entry in entries {
    let (key, value) = entry
    match key {
      "at" => () // consumed above
      "source" =>
        source = Some(
          parse_sheet_range(
            expect_string(value, file~, context="\{context} 'source'"),
            file~,
            what="\{context} 'source'",
          ),
        )
      "rows" | "columns" | "filters" => {
        let fields = load_pivot_fields(value, file~, context~, axis=key)
        match key {
          "rows" => rows = fields
          "columns" => columns = fields
          _ => filters = fields
        }
      }
      "values" => values = load_pivot_values(value, file~, context~)
      "name" =>
        name = Some(expect_string(value, file~, context="\{context} 'name'"))
      "style" =>
        style = Some(
          check_numbered_style(
            expect_string(value, file~, context="\{context} 'style'"),
            @model.pivot_style_families,
            file~,
            what="pivot style",
            context~,
          ),
        )
      "row_grand_totals" =>
        row_grand_totals = expect_bool(
          value,
          file~,
          context="\{context} '\{key}'",
        )
      "column_grand_totals" =>
        column_grand_totals = expect_bool(
          value,
          file~,
          context="\{context} '\{key}'",
        )
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in \{context} (expected 'at', 'source', 'rows', 'columns', 'filters', 'values', 'name', 'style', 'row_grand_totals', or 'column_grand_totals')",
        )
    }
  }
  guard source is Some(source) else {
    raise schema_error(file~, "\{context} is missing required key 'source'")
  }
  // A pivot laid out with filters alone summarizes nothing: the body would be
  // empty and the filters would have nothing to filter.
  guard !(rows.is_empty() && columns.is_empty() && values.is_empty()) else {
    raise schema_error(
      file~,
      "\{context} lays out no fields (expected 'rows', 'columns', or 'values')",
    )
  }
  {
    at,
    source,
    rows,
    columns,
    filters,
    values,
    name,
    style,
    row_grand_totals,
    column_grand_totals,
  }
}

///|
/// A grouping axis: a sequence of field names, or of `{ field, name }` mappings
/// where the pivot should call one something else.
fn load_pivot_fields(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
  axis~ : String,
) -> Array[@model.PivotField] raise @diag.SchemaError {
  let what = "\{context} '\{axis}'"
  let fields : Array[@model.PivotField] = []
  for item in expect_seq(node, file~, context=what) {
    if item is @yaml.Str(field) {
      fields.push({ field, name: None, })
      continue
    }
    let mut field = None
    let mut name = None
    for entry in expect_map(item, file~, context="a \{what} field") {
      let (key, value) = entry
      match key {
        "field" =>
          field = Some(expect_string(value, file~, context="\{what} 'field'"))
        "name" =>
          name = Some(expect_string(value, file~, context="\{what} 'name'"))
        _ =>
          raise schema_error(
            file~,
            "unknown key '\{key}' in a \{what} field (expected 'field' or 'name')",
          )
      }
    }
    guard field is Some(field) else {
      raise schema_error(
        file~,
        "a \{what} field is missing required key 'field'",
      )
    }
    fields.push({ field, name, })
  }
  fields
}

///|
/// A pivot's `values:` — the fields aggregated in the body. A bare name sums,
/// which is what Excel does with a numeric field dropped there.
fn load_pivot_values(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> Array[@model.PivotValue] raise @diag.SchemaError {
  let what = "\{context} 'values'"
  let values : Array[@model.PivotValue] = []
  for item in expect_seq(node, file~, context=what) {
    if item is @yaml.Str(field) {
      values.push({ field, function: Sum, name: None, })
      continue
    }
    let mut field = None
    let mut function = @model.Sum
    let mut name = None
    for entry in expect_map(item, file~, context="a \{what} field") {
      let (key, value) = entry
      match key {
        "field" =>
          field = Some(expect_string(value, file~, context="\{what} 'field'"))
        "function" =>
          function = named(
            pivot_functions,
            expect_string(value, file~, context="\{what} 'function'"),
            file~,
            what="pivot function",
            context=what,
          )
        "name" =>
          name = Some(expect_string(value, file~, context="\{what} 'name'"))
        _ =>
          raise schema_error(
            file~,
            "unknown key '\{key}' in a \{what} field (expected 'field', 'function', or 'name')",
          )
      }
    }
    guard field is Some(field) else {
      raise schema_error(
        file~,
        "a \{what} field is missing required key 'field'",
      )
    }
    values.push({ field, function, name, })
  }
  values
}

///|
/// Everything about a pivot that only the finished workbook can answer: that its
/// source is a region with a header row and rows beneath, that it names a sheet
/// the workbook has, that every field it lays out is a column of that header,
/// and that it is not drawn over the cells it summarizes.
///
/// Each of these is otherwise an error from inside the backend — or, worse, a
/// workbook Excel opens and then quietly refuses to refresh.
fn check_pivots(
  workbook : @model.Workbook,
  file~ : String,
) -> Unit raise @diag.SchemaError {
  for sheet in workbook.sheets {
    for pivot in sheet.pivots {
      let context = "pivot '\{pivot.at.to_a1()}' on sheet '\{sheet.name}'"
      let source_name = pivot.source.sheet.unwrap_or(sheet.name)
      guard workbook.sheet(source_name) is Some(source_sheet) else {
        raise schema_error(
          file~,
          "\{context} summarizes sheet '\{source_name}', which is not declared",
        )
      }
      let source = pivot.source.range
      // Excel builds a pivot out of a header row and the rows beneath it, and
      // needs at least one of each — and more than one column to group by.
      guard source.bottom_right.row > source.top_left.row &&
        source.bottom_right.col > source.top_left.col else {
        raise schema_error(
          file~,
          "\{context} summarizes '\{source.to_a1()}', which is not a region with a header row and rows beneath it",
        )
      }
      // The backend writes both halves of `Sheet!A1:D7` into the pivot's XML
      // after splitting on the first `!`, and Excel lets a sheet name hold one.
      // Such a name would silently summarize a sheet that does not exist.
      for named in [sheet.name, source_name] {
        guard !named.contains("!") else {
          raise schema_error(
            file~,
            "\{context} names sheet '\{named}', and a pivot cannot reference a sheet whose name holds '!'",
          )
        }
      }
      if source_name == sheet.name && overlaps(pivot.at, source) {
        raise schema_error(
          file~,
          "\{context} is drawn over the cells it summarizes at '\{source.to_a1()}'",
        )
      }
      check_pivot_fields(source_sheet, pivot, file~, context~)
    }
  }
}

///|
/// Every field a pivot lays out must name a column of its source's header row.
/// The backend reports an unknown one as `pivot field not found`, which says
/// nothing about where the mistake was written.
fn check_pivot_fields(
  source_sheet : @model.Sheet,
  pivot : @model.Pivot,
  file~ : String,
  context~ : String,
) -> Unit raise @diag.SchemaError {
  let source = pivot.source.range
  let headers = header_names(source_sheet, source)
  let width = source.bottom_right.col - source.top_left.col + 1
  guard headers.length() == width else {
    raise schema_error(
      file~,
      "\{context} summarizes '\{source.to_a1()}', whose top row does not name every column, as text",
    )
  }
  let named : Array[String] = []
  for field in pivot.rows {
    named.push(field.field)
  }
  for field in pivot.columns {
    named.push(field.field)
  }
  for field in pivot.filters {
    named.push(field.field)
  }
  for value in pivot.values {
    named.push(value.field)
  }
  for field in named {
    guard headers.contains(field) else {
      raise schema_error(
        file~,
        "\{context} lays out field '\{field}', which its source does not have (it has \{headers.join(", ")})",
      )
    }
  }
}
