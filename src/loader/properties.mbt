///|
/// The top-level `properties:` mapping. Every key is optional, and one left out
/// is left out of the file too.
fn load_properties(
  node : @yaml.Node,
  file~ : String,
) -> @model.DocumentProperties raise @diag.SchemaError {
  let mut title = None
  let mut subject = None
  let mut author = None
  let mut keywords = None
  let mut description = None
  let mut category = None
  let mut status = None
  let mut language = None
  let mut version = None
  let mut company = None
  let custom = []
  for entry in expect_map(node, file~, context="'properties'") {
    let (key, value) = entry
    // Every one but `custom` is free text; read it once here.
    let text = () => {
      Some(expect_string(value, file~, context="'properties' '\{key}'"))
    }
    match key {
      "title" => title = text()
      "subject" => subject = text()
      "author" => author = text()
      "keywords" => keywords = text()
      "description" => description = text()
      "category" => category = text()
      "status" => status = text()
      "language" => language = text()
      "version" => version = text()
      "company" => company = text()
      "custom" => load_custom_properties(value, custom, file~)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in 'properties' (expected 'title', 'subject', 'author', 'keywords', 'description', 'category', 'status', 'language', 'version', 'company', or 'custom')",
        )
    }
  }
  {
    title,
    subject,
    author,
    keywords,
    description,
    category,
    status,
    language,
    version,
    company,
    custom,
  }
}

///|
/// The `properties.custom:` mapping — names of the author's own devising, each
/// holding a scalar. Order is kept so the file is deterministic.
fn load_custom_properties(
  node : @yaml.Node,
  into : Array[@model.CustomProperty],
  file~ : String,
) -> Unit raise @diag.SchemaError {
  // A repeated name cannot reach here: the YAML parser rejects a duplicate
  // mapping key outright, and with a line and column this layer could not add.
  for entry in expect_map(node, file~, context="'properties' 'custom'") {
    let (name, value) = entry
    let context = "custom property '\{name}'"
    let value : @model.PropertyValue = match
      expect_scalar(value, file~, context~) {
      @yaml.Int(number) => Number(number.to_double())
      @yaml.Float(number) => Number(number)
      @yaml.Bool(flag) => Bool(flag)
      other => Text(scalar_text(other))
    }
    into.push({ name, value, })
  }
}

///|
/// The top-level `calc:` mapping — when Excel recalculates. `yxl` never
/// evaluates a formula, so this only tells Excel what to do on open.
fn load_calc(
  node : @yaml.Node,
  file~ : String,
) -> @model.CalcSettings raise @diag.SchemaError {
  let mut mode = None
  let mut on_load = None
  for entry in expect_map(node, file~, context="'calc'") {
    let (key, value) = entry
    match key {
      "mode" =>
        mode = Some(
          match expect_string(value, file~, context="'calc' 'mode'") {
            "automatic" => @model.Automatic
            "automatic_no_tables" => @model.AutomaticNoTables
            "manual" => @model.Manual
            other =>
              raise schema_error(
                file~,
                "unknown calc mode '\{other}' (expected 'automatic', 'automatic_no_tables', or 'manual')",
              )
          },
        )
      "on_load" =>
        on_load = Some(expect_bool(value, file~, context="'calc' 'on_load'"))
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in 'calc' (expected 'mode' or 'on_load')",
        )
    }
  }
  guard mode is Some(_) || on_load is Some(_) else {
    raise schema_error(
      file~,
      "'calc' sets nothing (expected 'mode' or 'on_load')",
    )
  }
  { mode, on_load, }
}

///|
/// The allowances a sheet's `protect:` may grant, in the order Excel's own
/// "Protect Sheet" dialog lists them. One table serves both the lookup and the
/// diagnostic, so the two cannot drift apart.
let protect_allowances : Array[String] = [
  "select_locked_cells", "select_unlocked_cells", "format_cells", "format_columns",
  "format_rows", "insert_columns", "insert_rows", "insert_hyperlinks", "delete_columns",
  "delete_rows", "sort", "auto_filter", "pivot_tables", "edit_objects", "edit_scenarios",
]

///|
/// A sheet's `protect:` — the sheet is locked, and `allow:` names what a reader
/// may still do. Excel's defaults apply to anything not named.
fn load_sheet_protection(
  node : @yaml.Node,
  file~ : String,
) -> @model.SheetProtection raise @diag.SchemaError {
  let protection = @model.SheetProtection()
  let mut password = None
  let mut allow : Array[(String, Bool)] = []
  for entry in expect_map(node, file~, context="sheet 'protect'") {
    let (key, value) = entry
    match key {
      "password" =>
        password = Some(
          expect_string(value, file~, context="sheet 'protect' 'password'"),
        )
      "allow" => allow = load_allowances(value, file~)
      _ =>
        raise schema_error(
          file~,
          "unknown key '\{key}' in sheet 'protect' (expected 'password' or 'allow')",
        )
    }
  }
  let with_allowances = allow.fold(init=protection, (protection, entry) => {
    let (name, allowed) = entry
    match name {
      "select_locked_cells" => { ..protection, select_locked_cells: allowed, }
      "select_unlocked_cells" =>
        { ..protection, select_unlocked_cells: allowed, }
      "format_cells" => { ..protection, format_cells: allowed, }
      "format_columns" => { ..protection, format_columns: allowed, }
      "format_rows" => { ..protection, format_rows: allowed, }
      "insert_columns" => { ..protection, insert_columns: allowed, }
      "insert_rows" => { ..protection, insert_rows: allowed, }
      "insert_hyperlinks" => { ..protection, insert_hyperlinks: allowed, }
      "delete_columns" => { ..protection, delete_columns: allowed, }
      "delete_rows" => { ..protection, delete_rows: allowed, }
      "sort" => { ..protection, sort: allowed, }
      "auto_filter" => { ..protection, auto_filter: allowed, }
      "pivot_tables" => { ..protection, pivot_tables: allowed, }
      "edit_objects" => { ..protection, edit_objects: allowed, }
      "edit_scenarios" => { ..protection, edit_scenarios: allowed, }
      // Unreachable: `load_allowances` already refused any other name.
      _ => protection
    }
  })
  { ..with_allowances, password, }
}

///|
/// The `allow:` mapping, validated key by key so a misspelt allowance is a
/// diagnostic rather than a permission that silently never applies.
fn load_allowances(
  node : @yaml.Node,
  file~ : String,
) -> Array[(String, Bool)] raise @diag.SchemaError {
  let allowances = []
  for entry in expect_map(node, file~, context="sheet 'protect' 'allow'") {
    let (key, value) = entry
    guard protect_allowances.contains(key) else {
      raise unknown_value(
        key,
        file~,
        what="allowance",
        context="sheet 'protect'",
        expected=protect_allowances.map(name => "'\{name}'"),
      )
    }
    allowances.push(
      (key, expect_bool(value, file~, context="sheet 'protect' allow '\{key}'")),
    )
  }
  allowances
}

///|
/// The top-level `protect:` — what a reader may not do to the workbook itself.
