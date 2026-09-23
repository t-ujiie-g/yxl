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
/// `{ total: … }` as a formula over the column's body, filtered by every
/// enclosing group.
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
        "MINIFS(\{body}\{criteria})"
      } else {
        "MIN(\{body})"
      }
    @yaml.Str("max") =>
      if grouped {
        "MAXIFS(\{body}\{criteria})"
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
