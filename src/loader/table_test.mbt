// External CSV and JSON data tables (`table.mbt`).

///|
test "a CSV table lands at its anchor, typed field by field" {
  let workbook = load_ok(
    "sheets:\n  - name: S\n    data:\n      - at: B2\n        csv: sales.csv\n",
    files={
      // A quoted field stays text; a bare one is read as what it looks like.
      "sales.csv": "APAC,2400000,true\nEMEA,1.5,\"007\"\n",
    },
  )
  let cells = workbook.sheets[0].cells
  assert_eq(cells.length(), 6)
  // The first field lands on the anchor, the rest run right and down.
  assert_eq(cells[0].pos, @units.CellRef::new(col=2, row=2))
  assert_eq(cells[0].value, @model.Text("APAC"))
  assert_eq(cells[1].pos, @units.CellRef::new(col=3, row=2))
  assert_eq(cells[1].value, @model.Number(2400000.0))
  assert_eq(cells[2].value, @model.Bool(true))
  assert_eq(cells[3].pos, @units.CellRef::new(col=2, row=3))
  assert_eq(cells[4].value, @model.Number(1.5))
  // Quoted, so the leading zeros survive instead of becoming the number 7.
  assert_eq(cells[5].value, @model.Text("007"))
}

///|
test "CSV quoting, blanks, ragged rows, and CRLF" {
  let workbook = load_ok(
    "sheets:\n  - name: S\n    data:\n      - at: A1\n        csv: t.csv\n",
    files={
      // A quoted field carrying a comma, a newline, and a doubled quote; an
      // empty field; a short row; CRLF line endings and a trailing newline.
      "t.csv": "\"a,b\",\"line\nbreak\",\"say \"\"hi\"\"\"\r\n,x\r\n",
    },
  )
  let cells = workbook.sheets[0].cells
  assert_eq(cells[0].value, @model.Text("a,b"))
  assert_eq(cells[1].value, @model.Text("line\nbreak"))
  assert_eq(cells[2].value, @model.Text("say \"hi\""))
  // The empty first field of row 2 wrote no cell at all; `x` sits in column B.
  assert_eq(cells.length(), 4)
  assert_eq(cells[3].pos, @units.CellRef::new(col=2, row=2))
  assert_eq(cells[3].value, @model.Text("x"))
}

///|
test "a JSON table of arrays, and of objects with named columns" {
  let arrays = load_ok(
    "sheets:\n  - name: S\n    data:\n      - at: A1\n        json: rows.json\n",
    files={
      "rows.json": "[[\"APAC\", 2400000, true], [\"EMEA\", null, false]]",
    },
  )
  let cells = arrays.sheets[0].cells
  // `null` is a blank cell, so row 2 writes only two of its three fields.
  assert_eq(cells.length(), 5)
  assert_eq(cells[0].value, @model.Text("APAC"))
  assert_eq(cells[1].value, @model.Number(2400000.0))
  assert_eq(cells[2].value, @model.Bool(true))
  assert_eq(cells[3].pos, @units.CellRef::new(col=1, row=2))
  assert_eq(cells[4].pos, @units.CellRef::new(col=3, row=2))
  // `columns` both selects the fields and fixes their order.
  let objects = load_ok(
    "sheets:\n  - name: S\n    data:\n      - at: A1\n        json: rows.json\n        columns: [revenue, region]\n",
    files={
      "rows.json": "[{\"region\": \"APAC\", \"revenue\": 24, \"note\": \"skip me\"}]",
    },
  )
  let picked = objects.sheets[0].cells
  assert_eq(picked.length(), 2)
  assert_eq(picked[0].value, @model.Number(24.0))
  assert_eq(picked[1].value, @model.Text("APAC"))
}

///|
test "a data table composes with band formatting and with plain cells" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: B
      #|        format: "#,##0"
      #|    cells:
      #|      A1: Region
      #|      B1: Revenue
      #|    data:
      #|      - at: A2
      #|        csv: sales.csv
      #|
    ),
    files={ "sales.csv": "APAC,2400000\n" },
  )
  let sheet = workbook.sheets[0]
  // Formatting comes from the column band, not from the data block — that is
  // what keeps data and formatting separable.
  assert_eq(sheet.columns[0].style.unwrap().number_format, Some("#,##0"))
  // Header cells and table cells coexist; the table's own cells carry no style.
  assert_eq(sheet.cells.length(), 4)
  assert_eq(sheet.cells[2].pos, @units.CellRef::new(col=1, row=2))
  assert_eq(sheet.cells[2].style, None)
}

///|
test "load rejects malformed data entries and unusable tables" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    data:\n      - csv: x.csv\n"),
    Some("spec.yaml: a 'data' entry is missing required key 'at'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    data:\n      - at: A1\n"),
    Some("spec.yaml: a 'data' entry needs a 'csv' or 'json' source"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    data:\n      - at: A1\n        csv: x.csv\n        json: x.json\n",
      files={ "x.csv": "", "x.json": "[]" },
    ),
    Some(
      "spec.yaml: a 'data' entry sets more than one source (a table comes from one file)",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    data:\n      - at: A1\n        csv: x.csv\n        columns: [a]\n",
      files={ "x.csv": "1\n" },
    ),
    Some(
      "spec.yaml: 'columns' names the fields of JSON objects; a CSV table's columns are its own",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    data:\n      - at: A1\n        csv: x.csv\n",
      files={ "x.csv": "\"unterminated\n" },
    ),
    Some("x.csv: CSV ends inside a quoted field"),
  )
  // Object rows need `columns`, because JSON key order is not dependable.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    data:\n      - at: A1\n        json: x.json\n",
      files={ "x.json": "[{\"a\": 1}]" },
    ),
    Some(
      "x.json: row 1 is a JSON object, so 'columns' must name the fields to take (object key order is not dependable)",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    data:\n      - at: A1\n        json: x.json\n        columns: [a, b]\n",
      files={ "x.json": "[{\"a\": 1}]" },
    ),
    Some("x.json: row 1 has no field 'b'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    data:\n      - at: A1\n        json: x.json\n",
      files={ "x.json": "{\"a\": 1}" },
    ),
    Some("x.json: a JSON table must be an array of rows"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    data:\n      - at: A1\n        json: x.json\n",
      files={ "x.json": "[[[1]]]" },
    ),
    Some(
      "x.json: row 1 has a field that is an array or object; a cell holds a string, number, boolean, or null",
    ),
  )
}
