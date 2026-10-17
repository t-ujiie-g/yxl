///|
test "a column needs a name that '{{name}}' can spell, once per sheet" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ width: 9 }]\n",
      ),
    ),
    Some("spec.yaml: a column of layout 'A1' is missing required key 'name'"),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: sales.cy }]\n",
      ),
    ),
    Some(
      "spec.yaml: column name 'sales.cy' in layout 'A1' must be letters, digits and '_', not starting with a digit",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: 1st }]\n",
      ),
    ),
    Some(
      "spec.yaml: column name '1st' in layout 'A1' must be letters, digits and '_', not starting with a digit",
    ),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a }]\n      - at: C1\n        rows: 1\n        columns: [{ name: a }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'C1' column 'a' reuses a name layout 'A1' already has on sheet '実績'",
    ),
  )
}

///|
test "a column's unknown key lists both its own keys and its band's" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, at: C }]\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'at' in layout 'A1' column 'a' (expected 'name', 'header', 'field', 'type', 'formula', 'conditional', 'body_style', 'width', 'style', 'format', 'hidden', or 'group')",
    ),
  )
}
