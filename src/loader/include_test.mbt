// `$include` expansion across files (`include.mbt`).

///|
test "an include stands wherever a node may, and nests" {
  let workbook = load_ok(
    (
      #|defs:
      #|  styles:
      #|    $include: theme.yaml
      #|sheets:
      #|  - name: Sales
      #|    columns:
      #|      $include: layout.yaml
      #|    cells:
      #|      $include: data.yaml
      #|
    ),
    files={
      // A `defs.styles` map, itself pulling one style from a third file.
      "theme.yaml": "header: { font: { bold: true } }\ntotal:\n  $include: total-style.yaml\n",
      "total-style.yaml": "font: { italic: true }\n",
      "layout.yaml": "- at: B\n  width: 14\n",
      "data.yaml": "A1: { value: Region, style: header }\nB1: 42\n",
    },
  )
  let sheet = workbook.sheets[0]
  // The included cells, columns, and styles all landed in the one model.
  assert_eq(sheet.cells[0].value, @model.Text("Region"))
  assert_eq(sheet.cells[0].style.unwrap().font.unwrap().bold, Some(true))
  assert_eq(sheet.cells[1].value, @model.Number(42.0))
  assert_eq(sheet.columns[0].size, Some(14.0))
  // The nested include resolved too: `total` came from a file inside a file.
  assert_eq(sheet.cells.length(), 2)
  let nested = load_ok(
    "sheets:\n  - name: S\n    cells:\n      A1: { value: x, style: total }\ndefs:\n  styles:\n    $include: theme.yaml\n",
    files={
      "theme.yaml": "total:\n  $include: total-style.yaml\n",
      "total-style.yaml": "font: { italic: true }\n",
    },
  )
  assert_eq(
    nested.sheets[0].cells[0].style.unwrap().font.unwrap().italic,
    Some(true),
  )
}

///|
test "a whole sheet, and a whole document, can be an include" {
  let workbook = load_ok("$include: workbook.yaml\n", files={
    "workbook.yaml": "sheets:\n  - $include: sheet.yaml\n",
    "sheet.yaml": "name: FromFile\ncells:\n  A1: hello\n",
  })
  assert_eq(workbook.sheets.length(), 1)
  assert_eq(workbook.sheets[0].name, "FromFile")
  assert_eq(workbook.sheets[0].cells[0].value, @model.Text("hello"))
}

///|
test "load rejects include cycles, siblings, and a non-text path" {
  // The cycle names the whole chain, so the offending edge is findable.
  assert_eq(
    schema_message("$include: a.yaml\n", files={
      "a.yaml": "$include: b.yaml\n",
      "b.yaml": "$include: a.yaml\n",
    }),
    Some("b.yaml: include cycle: spec.yaml -> a.yaml -> b.yaml -> a.yaml"),
  )
  // A file including itself is the shortest cycle.
  assert_eq(
    schema_message("$include: self.yaml\n", files={
      "self.yaml": "$include: self.yaml\n",
    }),
    Some("self.yaml: include cycle: spec.yaml -> self.yaml -> self.yaml"),
  )
  // An include replaces its whole node, so siblings would be dropped.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      $include: data.yaml\n      A1: kept?\n",
      files={ "data.yaml": "B1: 1\n" },
    ),
    Some(
      "spec.yaml: '$include' cannot be combined with other keys (it replaces the whole node)",
    ),
  )
  assert_eq(
    schema_message("sheets:\n  $include: 42\n"),
    Some("spec.yaml: '$include' must be text"),
  )
}

///|
test "a diagnostic in an included file names that file, not the including one" {
  // The schema error is in data.yaml, and the message says so.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      $include: data.yaml\n",
      files={ "data.yaml": "ZZ: 1\n" },
    ),
    Some("spec.yaml: 'ZZ' is not a valid A1 cell reference"),
  )
  // A *syntax* error in an included file is reported against that file.
  assert_eq(
    schema_message("sheets:\n  $include: broken.yaml\n", files={
      "broken.yaml": "- [unclosed\n",
    }),
    // The parser library's error renders as a bare type name today; carrying its
    // line/col through is Phase 8's rich-diagnostics work.
    Some(
      "broken.yaml: invalid YAML: moonbit-community/yaml.YamlError.YamlError",
    ),
  )
}

///|
test "a spec that includes without a resolver fails rather than guessing" {
  let document = @yaml.parse(
    "sheets:\n  $include: data.yaml\n",
    file="spec.yaml",
  )
  let message = try {
    @loader.load(document, file="spec.yaml") |> ignore
    None
  } catch {
    @diag.SchemaError(d) => Some(d.render())
    other => Some(other.to_string())
  }
  assert_eq(
    message,
    Some(
      "spec.yaml: cannot resolve '$include: data.yaml' — this caller provides no way to read files",
    ),
  )
}
