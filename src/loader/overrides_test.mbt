///|
/// A sheet holding a cell, a filled range beside it, and `body` as the
/// workbook's `overrides:` entries.
fn override_spec(body : String) -> String {
  (
    #|sheets:
    #|  - name: Sales
    #|    cells:
    #|      A1: from the template
    #|      A2: 100
    #|    formulas:
    #|      - at: C2:C4
    #|        formula: "A2*2"
    #|overrides:
    #|
  ) +
  body
}

///|
/// The sole override a spec loads.
fn loaded_override(body : String) -> @model.Override raise {
  let overrides = load_ok(override_spec(body)).overrides
  assert_eq(overrides.length(), 1)
  overrides[0]
}

///|
test "an override loads its sheet, its cell, its value, and its reason" {
  let entry = loaded_override(
    "  - at: Sales!A1\n    value: by hand\n    reason: 監査対応で当期のみ手修正\n",
  )
  assert_eq(entry.sheet, "Sales")
  assert_eq(entry.at.to_a1(), "A1")
  assert_eq(entry.value, Some(@model.Text("by hand")))
  assert_eq(entry.reason, Some("監査対応で当期のみ手修正"))
  assert_eq(entry.style, None)
}

///|
test "a reason is optional" {
  assert_eq(
    loaded_override("  - at: Sales!A1\n    value: by hand\n").reason,
    None,
  )
}

///|
test "the facets are independent: a style alone leaves the value alone" {
  let entry = loaded_override(
    "  - at: Sales!A1\n    style: { font: { bold: true } }\n",
  )
  assert_eq(entry.value, None)
  assert_true(entry.style is Some(_))
}

///|
test "a 'format' alone is a style facet, as it is on a cell" {
  let entry = loaded_override("  - at: Sales!A2\n    format: \"0.00%\"\n")
  assert_eq(entry.value, None)
  assert_eq(entry.style.unwrap().number_format, Some("0.00%"))
}

///|
test "an override carries the whole cell grammar" {
  assert_eq(
    loaded_override("  - at: Sales!C3\n    formula: \"=D3\"\n").value,
    Some(@model.Formula(formula="D3", cached=None)),
  )
  assert_eq(
    loaded_override(
      "  - at: Sales!A2\n    value: \"2026-03-31\"\n    type: date\n",
    ).value,
    Some(@model.Date(@units.DateTime::parse("2026-03-31").unwrap())),
  )
}

///|
test "an override may land inside a filled range, off its anchor" {
  assert_eq(
    loaded_override("  - at: Sales!C3\n    value: 0\n").at.to_a1(),
    "C3",
  )
}

///|
test "an override may land on a row a table wrote" {
  // The case the layer exists for: the value comes from a file the source
  // system refreshes, and one cell of it is wrong this month.
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: Sales
      #|    data:
      #|      - at: A1
      #|        values: [[APAC, 2400000], [EMEA, 1750000]]
      #|overrides:
      #|  - at: Sales!B2
      #|    value: 2450000
      #|    reason: 訂正版が間に合わなかった
      #|
    ),
  )
  assert_eq(workbook.overrides[0].value, Some(@model.Number(2450000.0)))
}

///|
test "several overrides load in declaration order" {
  let overrides = load_ok(
      override_spec(
        "  - at: Sales!A1\n    value: first\n  - at: Sales!A2\n    value: 1\n",
      ),
    ).overrides
  assert_eq(overrides.length(), 2)
  assert_eq(overrides[0].at.to_a1(), "A1")
  assert_eq(overrides[1].at.to_a1(), "A2")
}

///|
test "an override is ordinary YAML: a parameter substitutes into one" {
  assert_eq(
    load_ok(
      "params:\n  note: 手修正\n" +
      override_spec("  - at: Sales!A1\n    value: \"${note}\"\n"),
    ).overrides[0].value,
    Some(@model.Text("手修正")),
  )
}

///|
test "a sheet name Excel would quote may be quoted here too" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: Q3 data
      #|    cells:
      #|      A1: from the template
      #|overrides:
      #|  - at: "'Q3 data'!A1"
      #|    value: by hand
      #|
    ),
  )
  assert_eq(workbook.overrides[0].sheet, "Q3 data")
}

///|
test "an 'at' naming no sheet is refused" {
  assert_eq(
    schema_message(override_spec("  - at: A1\n    value: by hand\n")),
    Some(
      "spec.yaml: override 'at' must name the sheet it lands on: 'A1' (write 'Sheet!A1')",
    ),
  )
}

///|
test "an 'at' spanning a range is refused" {
  // A range would make this a second way to style a region, which is what keeps
  // `overrides:` countable as a list of exceptions (ADR-018).
  assert_eq(
    schema_message(override_spec("  - at: Sales!A1:B2\n    value: by hand\n")),
    Some(
      "spec.yaml: override 'at' takes a single cell, not the range 'Sales!A1:B2'; write one entry per cell",
    ),
  )
}

///|
test "an override needs an 'at', and refuses an unknown key" {
  assert_eq(
    schema_message(override_spec("  - value: by hand\n")),
    Some("spec.yaml: an override is missing required key 'at'"),
  )
  assert_eq(
    schema_message(override_spec("  - at: Sales!A1\n    because: why\n")),
    Some(
      "spec.yaml: unknown key 'because' in override 'Sales!A1' (expected 'at', 'reason', 'value', 'formula', 'rich', 'type', 'format', or 'style')",
    ),
  )
}

///|
test "an override that changes no facet is refused" {
  assert_eq(
    schema_message(override_spec("  - at: Sales!A1\n    reason: because\n")),
    Some(
      "spec.yaml: override 'Sales!A1' changes nothing (expected a 'value', a 'formula', a 'rich', a 'style', or a 'format')",
    ),
  )
}

///|
test "an override of an undeclared sheet is refused" {
  assert_eq(
    schema_message(override_spec("  - at: Costs!A1\n    value: by hand\n")),
    Some(
      "spec.yaml: override 'Costs!A1' names sheet 'Costs', which is not declared",
    ),
  )
}

///|
test "one cell has one override" {
  assert_eq(
    schema_message(
      override_spec(
        "  - at: Sales!A1\n    value: first\n  - at: Sales!A1\n    style: { font: { bold: true } }\n",
      ),
    ),
    Some(
      "spec.yaml: override 'Sales!A1' is declared twice; one cell has one override",
    ),
  )
}

///|
test "a filled range's anchor may not be overridden" {
  // The shared formula is stored there, and the rest of the range follows it —
  // so replacing that cell would take the formula away from every other row.
  assert_eq(
    schema_message(override_spec("  - at: Sales!C2\n    value: 0\n")),
    Some(
      "spec.yaml: override 'Sales!C2' is the anchor of formula range 'C2:C4', where the shared formula is stored; override another cell of the range, or start the range below it",
    ),
  )
}

///|
test "an override with nothing to override is refused" {
  assert_eq(
    schema_message(override_spec("  - at: Sales!Z9\n    value: by hand\n")),
    Some(
      "spec.yaml: override 'Sales!Z9' has nothing to override: no 'cells', 'data', or 'formulas' entry writes that cell — write it as a 'cells' entry instead",
    ),
  )
}
