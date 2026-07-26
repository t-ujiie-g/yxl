// Loading the top-level `properties:` and `calc:` — what the workbook says
// about itself, and how Excel recalculates when it opens.

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
    into.push({ name, value })
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
  { mode, on_load }
}
