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
