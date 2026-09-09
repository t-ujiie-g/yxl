///|
/// A sheet's `pivots:` block.
fn pivots(sheet : @model.Sheet) -> @yaml.Node {
  let rendered = []
  for pivot in sheet.pivots {
    let entries = [
      ("at", @yaml.Str(pivot.at.to_a1())),
      ("source", @yaml.Str(sheet_range(pivot.source))),
    ]
    if pivot.name is Some(name) {
      entries.push(("name", @yaml.Str(name)))
    }
    for
      axis in [
        ("rows", pivot.rows),
        ("columns", pivot.columns),
        ("filters", pivot.filters),
      ] {
      let (key, fields) = axis
      if !fields.is_empty() {
        entries.push((key, pivot_fields(fields)))
      }
    }
    if !pivot.values.is_empty() {
      entries.push(("values", pivot_values(pivot.values)))
    }
    if pivot.style is Some(style) {
      entries.push(("style", @yaml.Str(style)))
    }
    // Both default to `true`, so only the turned-off half is worth writing.
    if !pivot.row_grand_totals {
      entries.push(("row_grand_totals", @yaml.Bool(false)))
    }
    if !pivot.column_grand_totals {
      entries.push(("column_grand_totals", @yaml.Bool(false)))
    }
    rendered.push(@yaml.Map(entries))
  }
  @yaml.Seq(rendered)
}

///|
/// A grouping axis: a bare name where the pivot calls the field what the source
/// does, and `{ field, name }` where it relabels one.
fn pivot_fields(fields : Array[@model.PivotField]) -> @yaml.Node {
  let rendered = []
  for field in fields {
    rendered.push(
      match field.name {
        Some(name) =>
          @yaml.Map([
            ("field", @yaml.Str(field.field)),
            ("name", @yaml.Str(name)),
          ])
        None => @yaml.Str(field.field)
      },
    )
  }
  @yaml.Seq(rendered)
}

///|
/// The fields aggregated in the body. A bare name means `sum`, which is what the
/// schema reads one as.
fn pivot_values(values : Array[@model.PivotValue]) -> @yaml.Node {
  let rendered = []
  for value in values {
    if value.function is Sum && value.name is None {
      rendered.push(@yaml.Str(value.field))
      continue
    }
    let fields = [
      ("field", @yaml.Str(value.field)),
      ("function", @yaml.Str(pivot_function(value.function))),
    ]
    if value.name is Some(name) {
      fields.push(("name", @yaml.Str(name)))
    }
    rendered.push(@yaml.Map(fields))
  }
  @yaml.Seq(rendered)
}

///|
/// The schema's word for an aggregation, the inverse of the loader's table.
fn pivot_function(function : @model.PivotFunction) -> String {
  match function {
    Sum => "sum"
    Count => "count"
    CountNumbers => "count_numbers"
    Average => "average"
    Max => "max"
    Min => "min"
    Product => "product"
    StdDev => "std_dev"
    StdDevP => "std_dev_p"
    Var => "var"
    VarP => "var_p"
  }
}
