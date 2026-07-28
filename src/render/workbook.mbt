// Rendering the workbook-level keys: the named definitions, what the workbook
// says about itself, and how Excel recalculates on open. Sheet protection is
// here too, since it is written in the same vocabulary.

///|
/// The `defs.values` and `defs.formulas` blocks, beside whatever `defs.styles`
/// the styles produced. `None` when the workbook declares neither.
fn defined_names(wb : @model.Workbook) -> Array[(String, @yaml.Node)] {
  let values = []
  let formulas = []
  for defined in wb.defined_names {
    match defined.refers_to {
      Formula(formula~, ..) => formulas.push((defined.name, @yaml.Str(formula)))
      Text(text) => values.push((defined.name, @yaml.Str(text)))
      Number(number) => values.push((defined.name, number_scalar(number)))
      Bool(flag) => values.push((defined.name, @yaml.Bool(flag)))
      Date(datetime) =>
        values.push((defined.name, @yaml.Str(date_text(datetime))))
      // A defined name holds one value; the richer cell kinds cannot reach here.
      _ => ()
    }
  }
  let blocks = []
  if !values.is_empty() {
    blocks.push(("values", @yaml.Map(values)))
  }
  if !formulas.is_empty() {
    blocks.push(("formulas", @yaml.Map(formulas)))
  }
  blocks
}

///|
/// The `properties:` block, with only the fields the workbook sets.
fn document_properties(properties : @model.DocumentProperties) -> @yaml.Node {
  let entries = []
  fn field(name : String, value : String?) -> Unit {
    if value is Some(value) {
      entries.push((name, @yaml.Str(value)))
    }
  }

  field("title", properties.title)
  field("subject", properties.subject)
  field("author", properties.author)
  field("keywords", properties.keywords)
  field("description", properties.description)
  field("category", properties.category)
  field("status", properties.status)
  field("language", properties.language)
  field("version", properties.version)
  field("company", properties.company)
  if !properties.custom.is_empty() {
    let custom = []
    for property in properties.custom {
      custom.push(
        (
          property.name,
          match property.value {
            Number(number) => number_scalar(number)
            Bool(flag) => @yaml.Bool(flag)
            Text(text) => @yaml.Str(text)
          },
        ),
      )
    }
    entries.push(("custom", @yaml.Map(custom)))
  }
  @yaml.Map(entries)
}

///|
/// The `calc:` block.
fn calc_settings(calc : @model.CalcSettings) -> @yaml.Node {
  let entries = []
  if calc.mode is Some(mode) {
    entries.push(
      (
        "mode",
        @yaml.Str(
          match mode {
            Automatic => "auto"
            AutomaticNoTables => "auto_no_tables"
            Manual => "manual"
          },
        ),
      ),
    )
  }
  if calc.on_load is Some(on_load) {
    entries.push(("on_load", @yaml.Bool(on_load)))
  }
  @yaml.Map(entries)
}

///|
/// A sheet's `protect:` block. Excel's dialog starts with cell selection allowed
/// and everything else blocked, and so does the schema, so only what differs
/// from that is written down.
fn sheet_protection(protection : @model.SheetProtection) -> @yaml.Node {
  let allowances = []
  fn allow(name : String, value : Bool, default_value : Bool) -> Unit {
    if value != default_value {
      allowances.push((name, @yaml.Bool(value)))
    }
  }

  allow("select_locked_cells", protection.select_locked_cells, true)
  allow("select_unlocked_cells", protection.select_unlocked_cells, true)
  allow("format_cells", protection.format_cells, false)
  allow("format_columns", protection.format_columns, false)
  allow("format_rows", protection.format_rows, false)
  allow("insert_columns", protection.insert_columns, false)
  allow("insert_rows", protection.insert_rows, false)
  allow("insert_hyperlinks", protection.insert_hyperlinks, false)
  allow("delete_columns", protection.delete_columns, false)
  allow("delete_rows", protection.delete_rows, false)
  allow("sort", protection.sort, false)
  allow("auto_filter", protection.auto_filter, false)
  allow("pivot_tables", protection.pivot_tables, false)
  allow("edit_objects", protection.edit_objects, false)
  allow("edit_scenarios", protection.edit_scenarios, false)
  let entries = []
  if protection.password is Some(password) {
    entries.push(("password", @yaml.Str(password)))
  }
  if !allowances.is_empty() {
    entries.push(("allow", @yaml.Map(allowances)))
  }
  @yaml.Map(entries)
}
