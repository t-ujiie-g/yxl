///|
/// A sheet holding a named table for a slicer to filter, plus `body`.
fn slicer_spec(body : String) -> String {
  (
    #|sheets:
    #|  - name: S
    #|    cells:
    #|      A1: Region
    #|      B1: Type
    #|      C1: Sales
    #|      A2: APAC
    #|      B2: Direct
    #|      C2: 2400
    #|    tables:
    #|      - at: A1:C4
    #|        name: Sales
    #|
  ) +
  body
}

///|
/// The sole slicer a spec loads.
fn loaded_slicer(body : String) -> @model.Slicer raise {
  let slicers = load_ok(slicer_spec("    slicers:\n" + body)).sheets[0].slicers
  assert_eq(slicers.length(), 1)
  slicers[0]
}

///|
test "a slicer loads its anchor, table, and column, the rest defaulted" {
  let slicer = loaded_slicer(
    "      - at: E1\n        table: Sales\n        column: Region\n",
  )
  assert_eq(slicer.at.to_a1(), "E1")
  assert_eq(slicer.table, "Sales")
  assert_eq(slicer.column, "Region")
  assert_eq(slicer.caption, None)
  assert_eq(slicer.width, None)
  assert_eq(slicer.height, None)
  assert_eq(slicer.header, None)
}

///|
test "a slicer loads its caption, size, and header toggle" {
  let slicer = loaded_slicer(
    (
      #|      - at: E1
      #|        table: Sales
      #|        column: Region
      #|        caption: Pick a region
      #|        size: { width: 240, height: 180 }
      #|        header: false
      #|
    ),
  )
  assert_eq(slicer.caption, Some("Pick a region"))
  assert_eq(slicer.width, Some(240))
  assert_eq(slicer.height, Some(180))
  assert_eq(slicer.header, Some(false))
}

///|
test "a slicer finds its table whatever the case, as Excel compares names" {
  let slicer = loaded_slicer(
    "      - at: E1\n        table: sales\n        column: Region\n",
  )
  assert_eq(slicer.table, "sales")
}

///|
test "a slicer needs its anchor, table, and column" {
  assert_eq(
    schema_message(
      slicer_spec(
        "    slicers:\n      - table: Sales\n        column: Region\n",
      ),
    ),
    Some("spec.yaml: a slicer is missing required key 'at'"),
  )
  assert_eq(
    schema_message(
      slicer_spec("    slicers:\n      - at: E1\n        column: Region\n"),
    ),
    Some("spec.yaml: slicer at 'E1' is missing required key 'table'"),
  )
  assert_eq(
    schema_message(
      slicer_spec("    slicers:\n      - at: E1\n        table: Sales\n"),
    ),
    Some("spec.yaml: slicer at 'E1' is missing required key 'column'"),
  )
}

///|
test "a slicer over a table nobody declares is a diagnostic" {
  assert_eq(
    schema_message(
      slicer_spec(
        "    slicers:\n      - at: E1\n        table: Orders\n        column: Region\n",
      ),
    ),
    Some(
      "spec.yaml: slicer at 'E1' on sheet 'S' filters table 'Orders', which no sheet declares — a slicer needs a table with that 'name:'",
    ),
  )
}

///|
test "a slicer over a column the table lacks names what it has" {
  assert_eq(
    schema_message(
      slicer_spec(
        "    slicers:\n      - at: E1\n        table: Sales\n        column: Segment\n",
      ),
    ),
    Some(
      "spec.yaml: slicer at 'E1' on sheet 'S' filters column 'Segment', which table 'Sales' does not have (it has Region, Type, Sales)",
    ),
  )
}

///|
test "a slicer rejects an unknown key" {
  assert_eq(
    schema_message(
      slicer_spec(
        "    slicers:\n      - at: E1\n        table: Sales\n        column: Region\n        style: dark\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'style' in slicer at 'E1' (expected 'at', 'table', 'column', 'caption', 'size', or 'header')",
    ),
  )
}
