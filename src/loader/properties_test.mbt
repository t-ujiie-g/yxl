// Schema tests for the top-level `properties:` and `calc:`.

///|
/// The document properties a spec loads.
fn loaded_properties(body : String) -> @model.DocumentProperties raise {
  let wb = load_ok("properties:\n" + body + "sheets:\n  - name: S\n")
  wb.properties.unwrap()
}

///|
test "every document property loads into its own field" {
  let properties = loaded_properties(
    (
      #|  title: Quarterly report
      #|  subject: Regional sales
      #|  author: Finance team
      #|  keywords: "sales, q3"
      #|  description: Revenue by region.
      #|  category: Reports
      #|  status: Final
      #|  language: en-GB
      #|  version: "1.2"
      #|  company: Example Ltd
      #|
    ),
  )
  assert_eq(properties.title, Some("Quarterly report"))
  assert_eq(properties.subject, Some("Regional sales"))
  assert_eq(properties.author, Some("Finance team"))
  assert_eq(properties.keywords, Some("sales, q3"))
  assert_eq(properties.description, Some("Revenue by region."))
  assert_eq(properties.category, Some("Reports"))
  assert_eq(properties.status, Some("Final"))
  assert_eq(properties.language, Some("en-GB"))
  assert_eq(properties.version, Some("1.2"))
  assert_eq(properties.company, Some("Example Ltd"))
  assert_true(properties.custom.is_empty())
}

///|
test "an unset property stays unset rather than becoming empty" {
  let properties = loaded_properties("  title: Only this\n")
  assert_eq(properties.title, Some("Only this"))
  assert_eq(properties.subject, None)
  assert_eq(properties.company, None)
}

///|
test "custom properties keep their order and their types" {
  let properties = loaded_properties(
    (
      #|  custom:
      #|    Reviewed by: J. Smith
      #|    Cost centre: 4210
      #|    Approved: true
      #|    Margin: 0.185
      #|
    ),
  )
  assert_eq(properties.custom.length(), 4)
  assert_eq(properties.custom[0].name, "Reviewed by")
  assert_eq(properties.custom[0].value, Text("J. Smith"))
  assert_eq(properties.custom[1].value, Number(4210.0))
  assert_eq(properties.custom[2].value, Bool(true))
  assert_eq(properties.custom[3].value, Number(0.185))
}

///|
/// A repeated name is caught a layer earlier, by the YAML parser, which reports
/// it with a line and column. Asserted here so the guarantee is pinned wherever
/// it happens to be enforced.
test "a repeated custom property is refused" {
  // Parsed here rather than through `schema_message`, which reports what
  // *loading* rejects and so never sees a parse error at all.
  let message = try {
    @yaml.parse(
      "properties:\n  custom:\n    Owner: A\n    Owner: B\nsheets:\n  - name: S\n",
      file="spec.yaml",
    )
    |> ignore
    None
  } catch {
    @diag.YamlError(diagnostic) => Some(diagnostic.render())
  }
  guard message is Some(message) else { fail("expected a diagnostic") }
  assert_true(message.contains("Owner: duplicated key in mapping"))
  // And with a position, which the loader could not have supplied (ADR-016).
  assert_true(message.contains("spec.yaml:4:"))
}

///|
test "a structured custom property value is refused" {
  assert_eq(
    schema_message(
      "properties:\n  custom:\n    Owner: { first: A }\nsheets:\n  - name: S\n",
    ),
    Some(
      "spec.yaml: custom property 'Owner' must be text, a number, or a boolean",
    ),
  )
}

///|
test "properties rejects an unknown key" {
  guard schema_message("properties:\n  writer: A\nsheets:\n  - name: S\n")
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_true(
    message.has_prefix("spec.yaml: unknown key 'writer' in 'properties'"),
  )
}

///|
test "each calc mode loads" {
  for
    entry in [
      ("automatic", @model.CalcMode::Automatic),
      ("automatic_no_tables", AutomaticNoTables),
      ("manual", Manual),
    ] {
    let (written, expected) = entry
    let wb = load_ok("calc:\n  mode: \{written}\nsheets:\n  - name: S\n")
    assert_eq(wb.calc.unwrap().mode, Some(expected))
  }
}

///|
test "calc takes on_load on its own" {
  let wb = load_ok("calc:\n  on_load: true\nsheets:\n  - name: S\n")
  let calc = wb.calc.unwrap()
  assert_eq(calc.mode, None)
  assert_eq(calc.on_load, Some(true))
}

///|
test "an empty calc block is a diagnostic rather than a no-op" {
  assert_eq(
    schema_message("calc: {}\nsheets:\n  - name: S\n"),
    Some("spec.yaml: 'calc' sets nothing (expected 'mode' or 'on_load')"),
  )
}

///|
test "an unknown calc mode is named in the diagnostic" {
  assert_eq(
    schema_message("calc:\n  mode: lazy\nsheets:\n  - name: S\n"),
    Some(
      "spec.yaml: unknown calc mode 'lazy' (expected 'automatic', 'automatic_no_tables', or 'manual')",
    ),
  )
}

///|
/// Sheet protection a spec loads.
fn loaded_sheet_protection(body : String) -> @model.SheetProtection raise {
  load_ok(sheet_spec(body)).sheets[0].protection.unwrap()
}

///|
test "protect on its own applies Excel's own defaults" {
  let protection = loaded_sheet_protection("    protect: {}\n")
  assert_eq(protection.password, None)
  // Excel's dialog opens with both selection boxes ticked and nothing else.
  assert_true(protection.select_locked_cells)
  assert_true(protection.select_unlocked_cells)
  assert_false(protection.format_cells)
  assert_false(protection.sort)
}

///|
test "an allowance grants or blocks exactly what it names" {
  let protection = loaded_sheet_protection(
    "    protect:\n      allow:\n        sort: true\n        format_cells: true\n        select_locked_cells: false\n",
  )
  assert_true(protection.sort)
  assert_true(protection.format_cells)
  assert_false(protection.select_locked_cells)
  // Untouched allowances keep their defaults.
  assert_true(protection.select_unlocked_cells)
  assert_false(protection.format_rows)
}

///|
test "every allowance Excel's dialog offers is accepted" {
  for
    name in [
      "select_locked_cells", "select_unlocked_cells", "format_cells", "format_columns",
      "format_rows", "insert_columns", "insert_rows", "insert_hyperlinks", "delete_columns",
      "delete_rows", "sort", "auto_filter", "pivot_tables", "edit_objects", "edit_scenarios",
    ] {
    let source = sheet_spec(
      "    protect:\n      allow:\n        \{name}: true\n",
    )
    assert_eq(schema_message(source), None)
  }
}

///|
test "a misspelt allowance is a diagnostic, not a permission that never applies" {
  guard schema_message(
      sheet_spec("    protect:\n      allow:\n        sorting: true\n"),
    )
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_true(
    message.has_prefix(
      "spec.yaml: unknown allowance 'sorting' in sheet 'protect'",
    ),
  )
  assert_true(message.contains("'sort'"))
}

///|
test "a sheet protection password loads" {
  let protection = loaded_sheet_protection(
    "    protect:\n      password: \"s3cret\"\n",
  )
  assert_eq(protection.password, Some("s3cret"))
}

///|
test "sheet protect rejects an unknown key" {
  assert_eq(
    schema_message(sheet_spec("    protect:\n      locked: true\n")),
    Some(
      "spec.yaml: unknown key 'locked' in sheet 'protect' (expected 'password' or 'allow')",
    ),
  )
}

///|
test "workbook protection is refused with the reason, whatever it holds" {
  // The backend writes <workbookProtection> out of CT_Workbook's element
  // order and Excel reports the file as corrupt, so the key is refused by
  // name — found by opening the output in Excel, not by the round trip.
  let expected = Some(
    "spec.yaml: top-level 'protect' is refused for now: the Excel backend writes the workbook protection out of schema order and Excel reports the file as corrupt — protect each sheet instead, until the upstream fix",
  )
  assert_eq(
    schema_message("protect:\n  structure: true\nsheets:\n  - name: S\n"),
    expected,
  )
  assert_eq(
    schema_message("protect:\n  anything: goes\nsheets:\n  - name: S\n"),
    expected,
  )
}

///|
test "a style's protection loads both halves" {
  let wb = load_ok(
    sheet_spec(
      "    cells:\n      A1: { value: 1, style: { protection: { locked: false, hidden: true } } }\n",
    ),
  )
  let protection = wb.sheets[0].cells[0].style.unwrap().protection.unwrap()
  assert_eq(protection.locked, Some(false))
  assert_eq(protection.hidden, Some(true))
}

///|
test "a style's protection that sets nothing is a diagnostic" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    cells:\n      A1: { value: 1, style: { protection: {} } }\n",
      ),
    ),
    Some(
      "spec.yaml: cell 'A1' style 'protection' sets nothing (expected 'locked' or 'hidden')",
    ),
  )
}

///|
test "a style's protection rejects an unknown key" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    cells:\n      A1: { value: 1, style: { protection: { frozen: true } } }\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'frozen' in cell 'A1' style 'protection' (expected 'locked' or 'hidden')",
    ),
  )
}
