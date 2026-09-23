///|
/// One entry of a layout's `footer:` (ADR-024): a row of cells by column name,
/// or a group repeating its entries once per value of a column.
priv enum FooterEntry {
  FooterRow(Array[(String, @yaml.Node)], @model.Style?)
  FooterGroup(String, GroupOrder, Array[FooterEntry])
}

///|
/// The order a group's values take. `Listed` also says which values get a row.
priv enum GroupOrder {
  InData
  Ascending
  Descending
  Listed(Array[@model.CellValue?])
}

///|
/// What a footer needs to know about the layout above it.
priv struct FooterScope {
  sheet : @model.Sheet
  columns : Array[(String, Int)]
  col_of : Map[String, Int]
  input_of : Map[String, Int]
  data : Rows
  body_first : Int
  body_last : Int
  context : String
  file : String
  defs : Defs
}

///|
let footer_totals : Array[String] = ["sum", "count", "average", "min", "max"]

///|
/// Read `footer:`. `groups` are the enclosing groups' columns, and `has_data`
/// whether the layout reads rows a group can take its values from.
fn load_footer_entries(
  node : @yaml.Node,
  scope : FooterScope,
  groups~ : Array[String],
  has_data~ : Bool,
) -> Array[FooterEntry] raise @diag.SchemaError {
  let file = scope.file
  let context = scope.context
  let items = expect_seq(node, file~, context="\{context} footer")
  guard !items.is_empty() else {
    raise schema_error(file~, "\{context} footer has no rows")
  }
  items.map(item => {
    let entries = expect_map(item, file~, context="a \{context} footer entry")
    if find_key(entries, "row") is Some(cells) {
      let mut style = None
      for entry in entries {
        match entry.0 {
          "row" => ()
          "style" =>
            style = combine_style(
              Some(entry.1),
              None,
              file~,
              defs=scope.defs,
              context="\{context} footer row style",
            )
          key =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in a \{context} footer row (expected 'row' or 'style')",
            )
        }
      }
      let cells = expect_map(cells, file~, context="a \{context} footer row")
      for cell in cells {
        guard scope.col_of.contains(cell.0) else {
          raise schema_error(
            file~,
            "a \{context} footer row names '\{cell.0}', which is not a column of the layout",
          )
        }
      }
      check_footer_merges(cells, scope)
      FooterRow(cells, style)
    } else if find_key(entries, "by") is Some(by_node) {
      let by = expect_string(by_node, file~, context="\{context} footer 'by'")
      let where_ = "\{context} footer group '\{by}'"
      guard scope.input_of.contains(by) else {
        raise schema_error(
          file~,
          "\{where_} must name a column the data fills (one without a 'formula')",
        )
      }
      guard !groups.contains(by) else {
        raise schema_error(file~, "\{where_} is nested inside itself")
      }
      let mut order = InData
      let mut rows = None
      for entry in entries {
        match entry.0 {
          "by" => ()
          "order" => order = load_group_order(entry.1, file~, context=where_)
          "rows" => rows = Some(entry.1)
          key =>
            raise schema_error(
              file~,
              "unknown key '\{key}' in \{where_} (expected 'by', 'order', or 'rows')",
            )
        }
      }
      guard rows is Some(rows) else {
        raise schema_error(file~, "\{where_} is missing required key 'rows'")
      }
      guard has_data || order is Listed(_) else {
        raise schema_error(
          file~,
          "\{where_} takes its values from the layout's data, and the layout reads none; list them in 'order'",
        )
      }
      FooterGroup(
        by,
        order,
        load_footer_entries(rows, scope, groups=[..groups, by], has_data~),
      )
    } else {
      raise schema_error(
        file~,
        "a \{context} footer entry is a 'row', or a group with 'by'",
      )
    }
  })
}

///|
fn load_group_order(
  node : @yaml.Node,
  file~ : String,
  context~ : String,
) -> GroupOrder raise @diag.SchemaError {
  match node {
    @yaml.Str("data") => InData
    @yaml.Str("asc") => Ascending
    @yaml.Str("desc") => Descending
    @yaml.Seq(items) => {
      let values : Array[@model.CellValue?] = []
      for item in items {
        let value = match item {
          @yaml.Null => None
          scalar =>
            Some(scalar_value(scalar, file~, context="\{context} 'order'"))
        }
        guard !values.contains(value) else {
          raise schema_error(
            file~,
            "\{context} 'order' lists '\{group_label(value)}' twice",
          )
        }
        values.push(value)
      }
      Listed(values)
    }
    _ =>
      raise schema_error(
        file~,
        "\{context} 'order' must be 'data', 'asc', 'desc', or a list of values",
      )
  }
}

///|
/// Write `entries` from `row` down and return the row after the last one.
/// `keys` are the enclosing groups' columns and values; `members` the data rows
/// inside them.
fn write_footer(
  entries : Array[FooterEntry],
  scope : FooterScope,
  keys~ : Array[(String, @model.CellValue?)],
  members~ : Array[Int],
  row~ : Int,
) -> Int raise @diag.SchemaError {
  let mut row = row
  for entry in entries {
    match entry {
      FooterRow(cells, style) => {
        guard row <= max_sheet_row else {
          raise schema_error(
            file=scope.file,
            "\{scope.context} footer runs past Excel's last row (\{max_sheet_row})",
          )
        }
        write_footer_row(cells, style, scope, keys~, row~)
        row += 1
      }
      FooterGroup(by, order, nested) => {
        let where_ = "\{scope.context} footer group '\{by}'"
        let field = scope.input_of[by]
        let value_of = (index : Int) => {
          scope.data[index].get(field).unwrap_or(None)
        }
        let present : Array[@model.CellValue?] = []
        for index in members {
          let value = value_of(index)
          if !present.contains(value) {
            present.push(value)
          }
        }
        let values = match order {
          InData => present
          Ascending => {
            present.sort_by(compare_group_values)
            present
          }
          Descending => {
            present.sort_by((a, b) => compare_group_values(b, a))
            present
          }
          Listed(listed) => {
            for value in present {
              guard listed.contains(value) else {
                raise schema_error(
                  file=scope.file,
                  "\{where_} 'order' leaves out '\{group_label(value)}', which the data holds; its rows would be in no subtotal",
                )
              }
            }
            listed
          }
        }
        for value in values {
          row = write_footer(
            nested,
            scope,
            keys=[..keys, (by, value)],
            members=members.filter(index => value_of(index) == value),
            row~,
          )
        }
      }
    }
  }
  row
}

///|
/// One footer row: each named cell, and a blank wearing the row's style in
/// every other column, so a fill or a rule runs the width of the layout.
fn write_footer_row(
  cells : Array[(String, @yaml.Node)],
  row_style : @model.Style?,
  scope : FooterScope,
  keys~ : Array[(String, @model.CellValue?)],
  row~ : Int,
) -> Unit raise @diag.SchemaError {
  let file = scope.file
  let mut covered_to = 0
  let mut cover_style = None
  for column in scope.columns {
    let (name, col) = column
    let at = @units.CellRef(col~, row~)
    let where_ = "\{scope.context} footer row \{row} column '\{name}'"
    if col <= covered_to {
      if cover_style is Some(style) {
        scope.sheet.set(at, Blank, style~)
      }
      continue
    }
    guard find_key(cells, name) is Some(node) else {
      if row_style is Some(style) {
        scope.sheet.set(at, Blank, style~)
      }
      continue
    }
    let merge_to = merge_target(node).map(target => scope.col_of[target])
    let node = match node {
      @yaml.Map(entries) =>
        @yaml.Map(entries.filter(entry => entry.0 != FOOTER_MERGE_KEY))
      other => other
    }
    let merged = (style : @model.Style?) => {
      if merge_to is Some(last) {
        scope.sheet.merge(at, @units.CellRef(col=last, row~))
        covered_to = last
        cover_style = style
      }
    }
    if node is @yaml.Map([("total", total)]) {
      let formula = total_formula(total, col, scope, keys~, context=where_)
      scope.sheet.set(at, Formula(formula~, cached=None), style?=row_style)
      merged(row_style)
      continue
    }
    let spelled = match node {
      @yaml.Str(text) =>
        @yaml.Str(interpolate_group_values(text, keys, file~, context=where_))
      @yaml.Map(entries) =>
        @yaml.Map(
          entries.map(entry => {
            match entry {
              ("value", @yaml.Str(text)) =>
                (
                  "value",
                  @yaml.Str(
                    interpolate_group_values(text, keys, file~, context=where_),
                  ),
                )
              ("formula", @yaml.Str(text)) =>
                (
                  "formula",
                  @yaml.Str(
                    expand_column_refs(
                      text,
                      scope.col_of,
                      row~,
                      file~,
                      context=where_,
                    ),
                  ),
                )
              other => other
            }
          }),
        )
      other => other
    }
    let (value, style) = load_cell(
      spelled,
      file~,
      reference=at.to_a1(),
      defs=scope.defs,
    )
    let style = @model.Style::layer(row_style, style)
    scope.sheet.set(at, value, style?)
    merged(style)
  }
}

///|
const FOOTER_MERGE_KEY : String = "merge_to"

///|
/// The column a footer cell's `merge_to:` names, if it has one.
fn merge_target(node : @yaml.Node) -> String? {
  guard node is @yaml.Map(entries) &&
    find_key(entries, FOOTER_MERGE_KEY) is Some(@yaml.Str(target)) else {
    return None
  }
  Some(target)
}

///|
/// A `merge_to:` names a column of the layout to the cell's right, and no cell
/// the row writes lies inside the span, where the merge would hide it.
fn check_footer_merges(
  cells : Array[(String, @yaml.Node)],
  scope : FooterScope,
) -> Unit raise @diag.SchemaError {
  for cell in cells {
    let (name, node) = cell
    guard node is @yaml.Map(entries) &&
      find_key(entries, FOOTER_MERGE_KEY) is Some(target_node) else {
      continue
    }
    let where_ = "a \{scope.context} footer cell '\{name}'"
    let target = expect_string(
      target_node,
      file=scope.file,
      context="\{where_} '\{FOOTER_MERGE_KEY}'",
    )
    guard scope.col_of.get(target) is Some(last) else {
      raise schema_error(
        file=scope.file,
        "\{where_} merges to '\{target}', which is not a column of the layout",
      )
    }
    let first = scope.col_of[name]
    guard last > first else {
      raise schema_error(
        file=scope.file,
        "\{where_} merges to '\{target}', which is not to its right",
      )
    }
    for other in cells {
      let col = scope.col_of[other.0]
      guard !(col > first && col <= last) else {
        raise schema_error(
          file=scope.file,
          "\{where_} merges over '\{other.0}', which the row also writes",
        )
      }
    }
  }
}

///|
/// `{ total: … }` as a formula over the column's body, filtered by every
/// enclosing group. `MINIFS`/`MAXIFS` postdate the file format, so Excel reads
/// them only under their `_xlfn.` names.
fn total_formula(
  node : @yaml.Node,
  col : Int,
  scope : FooterScope,
  keys~ : Array[(String, @model.CellValue?)],
  context~ : String,
) -> String raise @diag.SchemaError {
  let range = (col : Int) => {
    let top = @units.CellRef(col~, row=scope.body_first).to_a1()
    let bottom = @units.CellRef(col~, row=scope.body_last).to_a1()
    "\{top}:\{bottom}"
  }
  let criteria = keys
    .map(key => ",\{range(scope.col_of[key.0])},\{group_criterion(key.1)}")
    .join("")
  let body = range(col)
  let grouped = !keys.is_empty()
  match node {
    @yaml.Str("sum") =>
      if grouped {
        "SUMIFS(\{body}\{criteria})"
      } else {
        "SUM(\{body})"
      }
    @yaml.Str("average") =>
      if grouped {
        "AVERAGEIFS(\{body}\{criteria})"
      } else {
        "AVERAGE(\{body})"
      }
    @yaml.Str("min") =>
      if grouped {
        "_xlfn.MINIFS(\{body}\{criteria})"
      } else {
        "MIN(\{body})"
      }
    @yaml.Str("max") =>
      if grouped {
        "_xlfn.MAXIFS(\{body}\{criteria})"
      } else {
        "MAX(\{body})"
      }
    @yaml.Str("count") =>
      if grouped {
        "COUNTIFS(\{body},\"<>\"\{criteria})"
      } else {
        "COUNTA(\{body})"
      }
    _ =>
      raise schema_error(
        file=scope.file,
        "\{context} 'total' must be \{or_list(footer_totals.map(t => "'\{t}'"))}",
      )
  }
}

///|
/// A group value as an `…IFS` criterion that matches it and nothing else: text
/// is compared with `=` and has the wildcards `~ * ?` escaped.
fn group_criterion(value : @model.CellValue?) -> String {
  match value {
    Some(Text(text)) => {
      let escaped = StringBuilder()
      for ch in text {
        match ch {
          '~' | '*' | '?' => {
            escaped.write_char('~')
            escaped.write_char(ch)
          }
          '"' => escaped.write_string("\"\"")
          _ => escaped.write_char(ch)
        }
      }
      "\"=\{escaped.to_string()}\""
    }
    Some(Bool(flag)) => if flag { "TRUE" } else { "FALSE" }
    Some(Number(_)) as number => group_label(number)
    _ => "\"\""
  }
}

///|
/// A group value as a label spells it: a whole number without a decimal point,
/// and a blank as nothing.
fn group_label(value : @model.CellValue?) -> String {
  match value {
    Some(Text(text)) => text
    Some(Number(number)) =>
      if number == number.floor() && number.abs() < 1.0e15 {
        number.to_int64().to_string()
      } else {
        number.to_string()
      }
    Some(Bool(flag)) => if flag { "TRUE" } else { "FALSE" }
    _ => ""
  }
}

///|
/// Numbers before text before anything else, a blank last; text by code point.
fn compare_group_values(a : @model.CellValue?, b : @model.CellValue?) -> Int {
  fn rank(value : @model.CellValue?) -> Int {
    match value {
      Some(Number(_)) => 0
      Some(Text(_)) => 1
      Some(_) => 2
      None => 3
    }
  }

  match (a, b) {
    (Some(Number(x)), Some(Number(y))) => x.compare(y)
    (Some(Text(x)), Some(Text(y))) => x.compare(y)
    _ => rank(a).compare(rank(b))
  }
}

///|
/// Replace each `{{name}}` in a footer label with the value of the enclosing
/// group on `name`; nothing else has a value while the spec compiles.
fn interpolate_group_values(
  text : String,
  keys : Array[(String, @model.CellValue?)],
  file~ : String,
  context~ : String,
) -> String raise @diag.SchemaError {
  substitute_names(text, in_formula=false, file~, context~, name => {
    guard keys.search_by(key => key.0 == name) is Some(index) else {
      let groups = keys.map(key => "'\{key.0}'")
      let known = if groups.is_empty() {
        "there is no enclosing 'by' group"
      } else {
        "the groups here are \{or_list(groups)}"
      }
      raise schema_error(
        file~,
        "\{context} spells '{{\{name}}}', but text can only spell a group's value, and \{known}",
      )
    }
    group_label(keys[index].1)
  })
}
