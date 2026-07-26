// Emitting what the workbook says about itself: the document properties Excel
// shows in its info pane, and how it recalculates on open.

///|
/// Write the document properties. Excel splits these across two parts — the
/// *core* properties every OPC package has, and the *application* ones Office
/// adds — so `company` is set apart from the rest.
fn apply_properties(
  backend : @xlsx.Workbook,
  properties : @model.DocumentProperties,
) -> Unit raise @xlsx.XlsxError {
  backend.set_core_properties(
    @xlsx.CoreProperties::with_values(
      title?=properties.title,
      subject?=properties.subject,
      creator?=properties.author,
      keywords?=properties.keywords,
      description?=properties.description,
      language?=properties.language,
      content_status?=properties.status,
      category?=properties.category,
      version?=properties.version,
    ),
  )
  if properties.company is Some(company) {
    backend.set_app_properties(@xlsx.AppProperties::with_values(company~))
  }
  for property in properties.custom {
    backend.set_custom_props(
      @xlsx.CustomProperty::new(
        property.name,
        Some(custom_value(property.value)),
      ),
    )
  }
}

///|
/// A custom property's value in the backend's tagged form.
fn custom_value(value : @model.PropertyValue) -> @xlsx.CustomPropertyValue {
  match value {
    // A whole number is written as an integer, so `4210` does not reach the
    // file as `4210.0`.
    Number(number) =>
      match exact_int(number) {
        Some(whole) => Integer(whole)
        None => Float(number)
      }
    Bool(flag) => Boolean(flag)
    Text(text) => Text(text)
  }
}

///|
/// Set how Excel recalculates. Only the fields the spec set are passed, so the
/// rest keep Excel's defaults.
fn apply_calc(
  backend : @xlsx.Workbook,
  calc : @model.CalcSettings,
) -> Unit raise @xlsx.XlsxError {
  backend.set_calc_props(
    Some(
      @xlsx.CalcPropsOptions::with_values(
        calc_mode?=calc.mode.map(calc_mode_code),
        full_calc_on_load?=calc.on_load,
      ),
    ),
  )
}

///|
/// The OOXML `calcMode` attribute for a model mode (ECMA-376 §18.18.10).
fn calc_mode_code(mode : @model.CalcMode) -> String {
  match mode {
    Automatic => "auto"
    AutomaticNoTables => "autoNoTable"
    Manual => "manual"
  }
}
