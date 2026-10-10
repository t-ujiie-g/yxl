///|
/// Write the document properties. Excel splits these across two parts — the
/// *core* properties every OPC package has, and the *application* ones Office
/// adds — so `company` is set apart from the rest.
fn apply_properties(
  backend : @xlsx.Workbook,
  properties : @model.DocumentProperties,
) -> Unit raise {
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
) -> Unit raise {
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

///|
/// Protect a sheet. The backend's options are *allowances*, exactly as the
/// model's are — it inverts them into OOXML's "locked" attributes itself — so
/// this is a field-for-field hand-over.
fn apply_sheet_protection(
  backend : @xlsx.Workbook,
  sheet_name : String,
  protection : @model.SheetProtection,
) -> Unit raise {
  backend.protect_sheet(
    sheet_name,
    @xlsx.SheetProtectionOptions::with_values(
      password?=protection.password,
      select_locked_cells=protection.select_locked_cells,
      select_unlocked_cells=protection.select_unlocked_cells,
      format_cells=protection.format_cells,
      format_columns=protection.format_columns,
      format_rows=protection.format_rows,
      insert_columns=protection.insert_columns,
      insert_rows=protection.insert_rows,
      insert_hyperlinks=protection.insert_hyperlinks,
      delete_columns=protection.delete_columns,
      delete_rows=protection.delete_rows,
      sort=protection.sort,
      auto_filter=protection.auto_filter,
      pivot_tables=protection.pivot_tables,
      edit_objects=protection.edit_objects,
      edit_scenarios=protection.edit_scenarios,
    ),
  )
}

///|
/// Lock the workbook's structure and/or windows.
fn apply_workbook_protection(
  backend : @xlsx.Workbook,
  protection : @model.WorkbookProtection,
) -> Unit raise {
  backend.protect_workbook(
    options=@xlsx.WorkbookProtectionOptions::with_values(
      password?=protection.password,
      lock_structure=protection.structure,
      lock_windows=protection.windows,
    ),
  )
}
