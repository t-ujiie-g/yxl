///|
/// A sheet with a three-column header row over one row of data, plus whatever
/// `body` adds — enough for a table over `A1:C2` to be well formed.
fn tabular_spec(body : String) -> String {
  sheet_spec(
    "    cells:\n      A1: Region\n      B1: Amount\n      C1: Share\n      A2: APAC\n      B2: 2400000\n      C2: 0.62\n" +
    body,
  )
}

///|
/// The sole table a spec loads.
fn loaded_table(body : String) -> @model.Table raise {
  let tables = load_ok(tabular_spec(body)).sheets[0].tables
  assert_eq(tables.length(), 1)
  tables[0]
}

///|
test "a table loads its range and Excel's own defaults" {
  let table = loaded_table("    tables:\n      - at: A1:C2\n")
  assert_eq(table.at.top_left.to_a1(), "A1")
  assert_eq(table.at.bottom_right.to_a1(), "C2")
  assert_eq(table.name, None)
  assert_eq(table.style, None)
  assert_true(table.banded_rows)
  assert_false(table.banded_columns)
  assert_false(table.first_column)
  assert_false(table.last_column)
}

///|
test "a table loads its name, style, and every toggle" {
  let table = loaded_table(
    (
      #|    tables:
      #|      - at: A1:C2
      #|        name: Sales
      #|        style: TableStyleDark3
      #|        banded_rows: false
      #|        banded_columns: true
      #|        first_column: true
      #|        last_column: true
      #|
    ),
  )
  assert_eq(table.name, Some("Sales"))
  assert_eq(table.style, Some("TableStyleDark3"))
  assert_false(table.banded_rows)
  assert_true(table.banded_columns)
  assert_true(table.first_column)
  assert_true(table.last_column)
}

///|
test "tables keep their declaration order" {
  let wb = load_ok(
    sheet_spec(
      "    cells:\n      A1: Region\n      A2: APAC\n      C1: Quarter\n      C2: Q3\n" +
      "    tables:\n      - at: A1:A2\n        name: First\n      - at: C1:C2\n        name: Second\n",
    ),
  )
  let tables = wb.sheets[0].tables
  assert_eq(tables.length(), 2)
  assert_eq(tables[0].name, Some("First"))
  assert_eq(tables[1].name, Some("Second"))
}

///|
test "each of Excel's style families is accepted at its bounds" {
  for
    style in [
      "TableStyleLight1", "TableStyleLight21", "TableStyleMedium1", "TableStyleMedium28",
      "TableStyleDark1", "TableStyleDark11",
    ] {
    assert_eq(
      schema_message(
        tabular_spec(
          "    tables:\n      - at: A1:C2\n        style: \{style}\n",
        ),
      ),
      None,
    )
  }
}

///|
test "a style outside Excel's set is a diagnostic naming the families" {
  assert_eq(
    schema_message(
      tabular_spec(
        "    tables:\n      - at: A1:C2\n        style: TableStyleLight22\n",
      ),
    ),
    Some(
      "spec.yaml: unknown table style 'TableStyleLight22' in table 'A1:C2' (expected 'TableStyleLight1'-'TableStyleLight21', 'TableStyleMedium1'-'TableStyleMedium28', or 'TableStyleDark1'-'TableStyleDark11')",
    ),
  )
}

///|
test "a one-row table is refused rather than quietly grown" {
  assert_eq(
    schema_message(tabular_spec("    tables:\n      - at: A1:C1\n")),
    Some(
      "spec.yaml: table 'A1:C1' covers one row; a table needs a header row and at least one row of data",
    ),
  )
}

///|
test "a table is missing required key 'at'" {
  assert_eq(
    schema_message(tabular_spec("    tables:\n      - name: Sales\n")),
    Some("spec.yaml: a table is missing required key 'at'"),
  )
}

///|
test "a table rejects an unknown key" {
  guard schema_message(
      tabular_spec("    tables:\n      - at: A1:C2\n        totals: true\n"),
    )
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_true(
    message.has_prefix("spec.yaml: unknown key 'totals' in table 'A1:C2'"),
  )
}

///|
test "a table name Excel would refuse is refused first, by name" {
  let refused = [
    ("2024 sales", "must start with a letter or an underscore"),
    ("Q3 sales", "may hold only letters, digits, '.' and '_' — no spaces"),
    ("C3", "is a cell reference, which Excel will not accept as a name"),
  ]
  for entry in refused {
    let (name, reason) = entry
    assert_eq(
      schema_message(
        tabular_spec(
          "    tables:\n      - at: A1:C2\n        name: \"\{name}\"\n",
        ),
      ),
      Some("spec.yaml: table name '\{name}' \{reason} (table 'A1:C2')"),
    )
  }
}

///|
test "an empty table name is refused" {
  assert_eq(
    schema_message(
      tabular_spec("    tables:\n      - at: A1:C2\n        name: \"\"\n"),
    ),
    Some("spec.yaml: table 'A1:C2' has an empty 'name'"),
  )
}

///|
test "a name of letters, digits, dots and underscores is accepted" {
  assert_eq(
    schema_message(
      tabular_spec(
        "    tables:\n      - at: A1:C2\n        name: _Sales.2024_Q3\n",
      ),
    ),
    None,
  )
}

///|
test "two tables cannot share a name, whichever sheets they are on" {
  let second = "  - name: T\n    cells:\n      A1: Region\n      A2: APAC\n    tables:\n      - at: A1:A2\n        name: sales\n"
  assert_eq(
    schema_message(
      tabular_spec("    tables:\n      - at: A1:C2\n        name: Sales\n") +
      second,
    ),
    Some(
      "spec.yaml: table 'A1:A2' on sheet 'T' is named 'sales', which table 'A1:C2' on sheet 'S' already uses",
    ),
  )
}

///|
test "two tables on a sheet cannot share a cell" {
  assert_eq(
    schema_message(
      tabular_spec(
        "    tables:\n      - at: A1:C2\n        name: First\n      - at: C1:C2\n        name: Second\n",
      ),
    ),
    Some(
      "spec.yaml: table 'C1:C2' on sheet 'S' overlaps the table at 'A1:C2'; Excel allows a cell in one table only",
    ),
  )
}

///|
test "a table and the sheet's own filter cannot share a cell" {
  assert_eq(
    schema_message(
      tabular_spec("    filter: A1:C9\n    tables:\n      - at: A1:C2\n"),
    ),
    Some(
      "spec.yaml: table 'A1:C2' on sheet 'S' overlaps the sheet's filter at 'A1:C9'; a table carries its own filter buttons",
    ),
  )
}

///|
test "a header cell left empty is a diagnostic, not an invented column name" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    cells:\n      A1: Region\n      A2: APAC\n    tables:\n      - at: A1:B2\n",
      ),
    ),
    Some(
      "spec.yaml: table 'A1:B2' on sheet 'S' has no column name at 'B1'; a table's top row must name every column, as text",
    ),
  )
}

///|
test "a numeric header is refused, since a column name is text" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    cells:\n      A1: Region\n      B1: 2024\n      A2: APAC\n    tables:\n      - at: A1:B2\n",
      ),
    ),
    Some(
      "spec.yaml: table 'A1:B2' on sheet 'S' has no column name at 'B1'; a table's top row must name every column, as text",
    ),
  )
}

///|
test "two columns cannot carry the same name" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    cells:\n      A1: Region\n      B1: region\n      A2: APAC\n    tables:\n      - at: A1:B2\n",
      ),
    ),
    Some(
      "spec.yaml: table 'A1:B2' on sheet 'S' names two columns 'region' (at 'B1'); Excel needs them distinct",
    ),
  )
}

///|
test "a table's headers may come from a data file" {
  let wb = load_ok(
    sheet_spec(
      "    data:\n      - at: A1\n        csv: sales.csv\n    tables:\n      - at: A1:B3\n        name: Sales\n",
    ),
    files={ "sales.csv": "Region,Amount\nAPAC,2400000\nEMEA,1200000\n" },
  )
  assert_eq(wb.sheets[0].tables[0].name, Some("Sales"))
}
