///|
/// SpreadsheetML's own namespace, which both of a pivot's parts are written in
/// (ECMA-376 §18.1).
const SHEET_NS : String = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

///|
/// The pivot tables on a sheet.
///
/// `declared` names the sheets that survived the read, because a pivot whose
/// source was skipped — a chart sheet, say — would compile to a spec the loader
/// refuses.
fn read_pivots(
  backend : @xlsx.Workbook,
  sheet : @model.Sheet,
  declared~ : Array[String],
  notes : Notes,
) -> Unit {
  guard backend.sheet(sheet.name) is Some(source) else { return }
  for pivot in source.pivot_tables {
    if read_pivot(pivot, sheet.name, declared, notes) is Some(recovered) {
      sheet.add_pivot(recovered)
    }
  }
}

///|
/// One pivot, or `None` with the reason already reported.
///
/// The two parts are read together: `table_xml` refers to its fields by index,
/// and the names those indices stand for live in `cache_definition_xml`.
fn read_pivot(
  pivot : @xlsx.PivotTable,
  sheet_name : String,
  declared : Array[String],
  notes : Notes,
) -> @model.Pivot? {
  let context = "a pivot table on '\{sheet_name}'"
  guard parse_xml(pivot.table_xml) is Some(definition) &&
    definition.ns == SHEET_NS &&
    definition.name == "pivotTableDefinition" else {
    notes.drop("\{context}, whose definition is not one this reader can follow")
    return None
  }
  guard definition.child(SHEET_NS, "location") is Some(location) &&
    location.attribute("ref") is Some(drawn) &&
    @model.CellRange::parse(drawn) is Some(at) else {
    notes.drop("\{context}, which is not drawn over a range the spec can name")
    return None
  }
  let context = "the pivot at '\{at.to_a1()}' on '\{sheet_name}'"
  guard read_pivot_source(pivot, context, declared, notes) is Some(source) else {
    return None
  }
  guard read_cache_field_names(pivot) is Some(cache_fields) else {
    notes.drop("\{context}, whose cache names none of the fields it summarizes")
    return None
  }
  // A `<pivotField>` carries the *display* name; the cache field at the same
  // index carries the source column's own. They line up by position.
  let display = definition
    .child(SHEET_NS, "pivotFields")
    .map(fields => fields.children_named(SHEET_NS, "pivotField"))
    .unwrap_or([])
  let axes : Array[Array[@model.PivotField]] = []
  for
    axis in [
      ("rowFields", "field", "x"),
      ("colFields", "field", "x"),
      ("pageFields", "pageField", "fld"),
    ] {
    let (block, child, index_attribute) = axis
    let fields = []
    for
      entry in definition
      .child(SHEET_NS, block)
      .map(found => found.children_named(SHEET_NS, child))
      .unwrap_or([]) {
      guard entry.attribute(index_attribute) is Some(written) &&
        field_index(written, cache_fields) is Some(index) else {
        notes.drop(
          "\{context}, which lays out a field its cache does not describe",
        )
        return None
      }
      let recovered : @model.PivotField = {
        field: cache_fields[index],
        name: relabel(display, index, cache_fields[index]),
      }
      fields.push(recovered)
    }
    axes.push(fields)
  }
  guard read_pivot_values(definition, cache_fields, context, notes)
    is Some(values) else {
    return None
  }
  // Excel's own pivots are in *compact* form and lay each field out with its
  // own sort; the schema states neither, so a spec built from one would rebuild
  // in outline form, unsorted. Said aloud rather than left to be noticed.
  if definition.attribute("compactData") is Some(compact) && compact != "0" {
    notes.drop(
      "\{context}'s compact layout, which the schema has no word for — it rebuilds in outline form, a field per column",
    )
  }
  if display.iter().any(field => field.attribute("sortType") is Some(_)) {
    notes.drop(
      "\{context}'s field sorting, which the schema has no word for — Excel sorts the rebuilt pivot by its own default",
    )
  }
  let style = definition
    .child(SHEET_NS, "pivotTableStyleInfo")
    .bind(info => info.attribute("name"))
  if style is Some(written) && !named_pivot_style(written) {
    notes.drop(
      "\{context}, which wears the style '\{written}' — one outside the families the spec names",
    )
    return None
  }
  Some({
    at,
    source,
    rows: axes[0],
    columns: axes[1],
    filters: axes[2],
    values,
    name: definition.attribute("name"),
    style,
    row_grand_totals: flag(definition, "rowGrandTotals"),
    column_grand_totals: flag(definition, "colGrandTotals"),
  })
}

///|
/// The cells a pivot summarizes, from its cache's `<worksheetSource>`.
fn read_pivot_source(
  pivot : @xlsx.PivotTable,
  context : String,
  declared : Array[String],
  notes : Notes,
) -> @model.SheetRange? {
  guard parse_xml(pivot.cache_definition_xml) is Some(cache) &&
    cache.child(SHEET_NS, "cacheSource") is Some(cache_source) else {
    notes.drop("\{context}, whose cache does not say what it summarizes")
    return None
  }
  guard cache_source.child(SHEET_NS, "worksheetSource") is Some(worksheet) else {
    notes.drop(
      "\{context}, which summarizes something other than a region of cells — an external source or another pivot, neither of which the spec can declare",
    )
    return None
  }
  // A `<worksheetSource>` may name a *table* instead of a range, which the
  // schema's `source:` cannot say.
  guard worksheet.attribute("ref") is Some(summarized) &&
    @model.CellRange::parse(summarized) is Some(range) else {
    notes.drop(
      "\{context}, which summarizes an Excel table rather than a range of cells",
    )
    return None
  }
  guard worksheet.attribute("sheet") is Some(name) else {
    notes.drop("\{context}, whose source names no sheet")
    return None
  }
  guard declared.contains(name) else {
    notes.drop(
      "\{context}, which summarizes '\{name}' — a sheet this spec does not declare",
    )
    return None
  }
  Some({ sheet: Some(name), range, })
}

///|
/// The `<cacheField>` names, in the order a `<pivotField>` index counts them.
fn read_cache_field_names(pivot : @xlsx.PivotTable) -> Array[String]? {
  guard parse_xml(pivot.cache_definition_xml) is Some(cache) &&
    cache.child(SHEET_NS, "cacheFields") is Some(fields) else {
    return None
  }
  let names = []
  for field in fields.children_named(SHEET_NS, "cacheField") {
    // A calculated field has a `formula` instead of a source column, so its
    // name resolves to nothing the spec's `source:` holds.
    guard field.attribute("name") is Some(name) &&
      field.attribute("formula") is None else {
      return None
    }
    names.push(name)
  }
  if names.is_empty() {
    None
  } else {
    Some(names)
  }
}

///|
/// The fields aggregated in the body.
fn read_pivot_values(
  definition : XmlElement,
  cache_fields : Array[String],
  context : String,
  notes : Notes,
) -> Array[@model.PivotValue]? {
  let values : Array[@model.PivotValue] = []
  for
    entry in definition
    .child(SHEET_NS, "dataFields")
    .map(fields => fields.children_named(SHEET_NS, "dataField"))
    .unwrap_or([]) {
    guard entry.attribute("fld") is Some(written) &&
      field_index(written, cache_fields) is Some(index) else {
      notes.drop(
        "\{context}, which aggregates a field its cache does not describe",
      )
      return None
    }
    // `subtotal` is optional and defaults to `sum` (ECMA-376 §18.10.1.19).
    let written = entry.attribute("subtotal").unwrap_or("sum")
    guard pivot_function(written) is Some(function) else {
      notes.drop(
        "\{context}, which aggregates with '\{written}' — a function the spec has no word for",
      )
      return None
    }
    if entry.attribute("numFmtId") is Some(_) {
      notes.drop(
        "\{context}'s number format on a value field, which the schema states per cell rather than per aggregation",
      )
    }
    values.push({
      field: cache_fields[index],
      function,
      name: relabelled(entry.attribute("name"), cache_fields[index]),
    })
  }
  Some(values)
}

///|
/// A `<field x>` / `<dataField fld>` index, if the cache describes that field.
fn field_index(written : String, cache_fields : Array[String]) -> Int? {
  let index = @string.parse_int(written) catch { _ => return None }
  if index >= 0 && index < cache_fields.length() {
    Some(index)
  } else {
    None
  }
}

///|
/// The display name a `<pivotField>` gives the field at `index`, or `None`
/// where it is the source column's own name and the spec would say nothing.
fn relabel(display : Array[XmlElement], index : Int, field : String) -> String? {
  guard index < display.length() else { return None }
  relabelled(display[index].attribute("name"), field)
}

///|
/// A written name, unless it merely repeats the field's own.
fn relabelled(written : String?, field : String) -> String? {
  match written {
    Some(name) => if name == field { None } else { Some(name) }
    None => None
  }
}

///|
/// A grand-total flag, which ECMA-376 §18.10.1.73 defaults to on.
fn flag(definition : XmlElement, name : String) -> Bool {
  match definition.attribute(name) {
    Some("0") | Some("false") => false
    _ => true
  }
}

///|
/// The spec's word for an OOXML aggregation (`ST_DataConsolidateFunction`).
fn pivot_function(written : String) -> @model.PivotFunction? {
  match written {
    "sum" => Some(Sum)
    "count" => Some(Count)
    "countNums" => Some(CountNumbers)
    "average" => Some(Average)
    "max" => Some(Max)
    "min" => Some(Min)
    "product" => Some(Product)
    "stdDev" => Some(StdDev)
    "stdDevp" => Some(StdDevP)
    "var" => Some(Var)
    "varp" => Some(VarP)
    _ => None
  }
}

///|
/// Whether a style name is one of the numbered families the schema spells.
fn named_pivot_style(written : String) -> Bool {
  for family in @model.pivot_style_families {
    let (prefix, count) = family
    if written.has_prefix(prefix) {
      let number = @string.parse_int(written[prefix.length():].to_owned()) catch {
        _ => continue
      }
      if number >= 1 && number <= count {
        return true
      }
    }
  }
  false
}
