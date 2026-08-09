///|
/// A sheet with a small calculation table, plus `body`.
fn formula_spec(body : String) -> String {
  (
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: Qty
    #|      B1: Price
    #|      A2: 3
    #|      B2: 250
    #|      A3: 7
    #|      B3: 125
    #|
  ) +
  body
}

///|
/// The sole formula range a spec loads.
fn loaded_formula(body : String) -> @model.FormulaRange raise {
  let ranges = load_ok(formula_spec("    formulas:\n" + body)).sheets[0].formulas
  assert_eq(ranges.length(), 1)
  ranges[0]
}

///|
test "a formula range loads its region and formula" {
  let range = loaded_formula("      - at: C2:C3\n        formula: \"A2*B2\"\n")
  assert_eq(range.at.to_a1(), "C2:C3")
  assert_eq(range.formula, "A2*B2")
}

///|
test "a leading '=' is accepted and stripped, as it is on a cell" {
  assert_eq(
    loaded_formula("      - at: C2:C3\n        formula: \"=A2*B2\"\n").formula,
    "A2*B2",
  )
}

///|
test "a range may be a single cell, and may span columns as well as rows" {
  assert_eq(
    loaded_formula("      - at: C2:C2\n        formula: \"A2*B2\"\n").at.to_a1(),
    "C2:C2",
  )
  assert_eq(
    loaded_formula("      - at: C2:D3\n        formula: \"A2*B2\"\n").at.to_a1(),
    "C2:D3",
  )
}

///|
test "several ranges load in declaration order" {
  let ranges = load_ok(
      formula_spec(
        "    formulas:\n      - at: C2:C3\n        formula: \"A2*B2\"\n      - at: D2:D3\n        formula: \"C2*2\"\n",
      ),
    ).sheets[0].formulas
  assert_eq(ranges.length(), 2)
  assert_eq(ranges[0].at.to_a1(), "C2:C3")
  assert_eq(ranges[1].at.to_a1(), "D2:D3")
}

///|
test "a formula range needs both its keys, and refuses an unknown one" {
  assert_eq(
    schema_message(formula_spec("    formulas:\n      - formula: \"A2*B2\"\n")),
    Some("spec.yaml: a formula range is missing required key 'at'"),
  )
  assert_eq(
    schema_message(formula_spec("    formulas:\n      - at: C2:C3\n")),
    Some("spec.yaml: formula range 'C2:C3' is missing required key 'formula'"),
  )
  assert_eq(
    schema_message(
      formula_spec(
        "    formulas:\n      - at: C2:C3\n        formula: \"A2*B2\"\n        style: header\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'style' in formula range 'C2:C3' (expected 'at' or 'formula')",
    ),
  )
}

///|
test "an 'at' that is not a range, and an empty formula, are diagnostics" {
  assert_eq(
    schema_message(
      formula_spec(
        "    formulas:\n      - at: C2\n        formula: \"A2*B2\"\n",
      ),
    ),
    Some("spec.yaml: formula range 'C2' must be 'TopLeft:BottomRight'"),
  )
  assert_eq(
    schema_message(
      formula_spec("    formulas:\n      - at: C2:C3\n        formula: \"\"\n"),
    ),
    Some("spec.yaml: formula range 'C2:C3' has an empty 'formula'"),
  )
}

///|
test "a '$ref' is refused, because a defined name would not shift per row" {
  let message = schema_message(
    formula_spec(
      "    formulas:\n      - at: C2:C3\n        formula: { $ref: subtotal }\n",
    ),
  )
  assert_true(message is Some(_))
  assert_true(
    message
    .unwrap()
    .has_prefix(
      "spec.yaml: formula range 'C2:C3' 'formula' cannot be a '$ref':",
    ),
  )
}

///|
test "two formula ranges may not overlap" {
  assert_eq(
    schema_message(
      formula_spec(
        "    formulas:\n      - at: C2:C5\n        formula: \"A2*B2\"\n      - at: C4:C8\n        formula: \"A4+B4\"\n",
      ),
    ),
    Some(
      "spec.yaml: formula range 'C4:C8' on sheet 'S' overlaps the one at 'C2:C5'; a cell can hold one formula",
    ),
  )
}

///|
test "a formula range may not cover a cell the sheet also writes" {
  // The collision is reported however the two are ordered, because the check
  // runs once the sheet is whole.
  assert_eq(
    schema_message(
      formula_spec(
        "    formulas:\n      - at: A2:A3\n        formula: \"1+1\"\n",
      ),
    ),
    Some(
      "spec.yaml: formula range 'A2:A3' on sheet 'S' covers 'A2', which the sheet also writes as a cell; split the range around it rather than letting one silently win",
    ),
  )
}

///|
test "an absurd range is refused rather than filled" {
  // A cell reference is not bounded to Excel's grid where it is parsed, so
  // without this a typo would build cells until the machine gave up.
  let message = schema_message(
    formula_spec(
      "    formulas:\n      - at: C2:ZZ9999999\n        formula: \"1\"\n",
    ),
  )
  assert_true(message is Some(_))
  assert_true(
    message
    .unwrap()
    .has_prefix("spec.yaml: formula range 'C2:ZZ9999999' covers "),
  )
  assert_true(message.unwrap().has_suffix("a formula range may fill"))
}

///|
test "a full column is within the ceiling" {
  assert_eq(
    loaded_formula("      - at: C1:C1048576\n        formula: \"1\"\n").at.to_a1(),
    "C1:C1048576",
  )
}
