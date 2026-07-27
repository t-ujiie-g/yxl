// Styles: inline mappings, the `defs.styles` block, references by name, and
// `extends:` inheritance (`style.mbt`, `defs.mbt`).

///|
test "load parses a full style: font, fill, border, alignment, and number format" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1:
      #|        value: 0.5
      #|        format: "0.00%"
      #|        style:
      #|          font: { bold: true, size: 12, name: Calibri, color: "FF0000" }
      #|          fill: "FFFF00"
      #|          align: { horizontal: center, vertical: middle, wrap: true }
      #|          border:
      #|            all: thin
      #|            bottom: { style: double, color: "000000" }
      #|
    ),
  )
  assert_eq(
    workbook.sheets[0].cells[0].style,
    Some(@model.Style::{
      number_format: Some("0.00%"),
      font: Some({
        bold: Some(true),
        italic: None,
        underline: None,
        strike: None,
        size: Some(12.0),
        name: Some("Calibri"),
        color: @units.Color::parse("FF0000"),
      }),
      fill: Some({ color: @units.Color::parse("FFFF00").unwrap() }),
      align: Some({
        horizontal: Some(Center),
        vertical: Some(Middle),
        wrap: Some(true),
      }),
      borders: Some({
        left: Some({ style: Thin, color: None }),
        right: Some({ style: Thin, color: None }),
        top: Some({ style: Thin, color: None }),
        bottom: Some({ style: Double, color: @units.Color::parse("000000") }),
      }),
      protection: None,
    }),
  )
}

///|
test "load rejects invalid style attributes" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { fill: \"red\" } }\n",
    ),
    Some("spec.yaml: cell 'A1' fill is not a valid hex color: 'red'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { align: { horizontal: middle } } }\n",
    ),
    Some(
      "spec.yaml: cell 'A1' has an unknown horizontal alignment 'middle' (expected 'left', 'center', 'right', 'fill', 'justify', or 'distributed')",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { border: wavy } }\n",
    ),
    Some(
      "spec.yaml: cell 'A1' has an unknown border style 'wavy' (expected 'thin', 'medium', 'thick', 'dashed', 'dotted', 'double', or 'hair')",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { glow: true } }\n",
    ),
    Some(
      "spec.yaml: unknown key 'glow' in cell 'A1' style (expected 'font', 'fill', 'border', 'align', 'protection', or 'extends')",
    ),
  )
}

///|
test "a style must be a name or a mapping, and an unknown vertical alignment is spelled out" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: 5 }\n",
    ),
    Some("spec.yaml: cell 'A1' style must be a mapping"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { align: { vertical: sideways } } }\n",
    ),
    Some(
      "spec.yaml: cell 'A1' has an unknown vertical alignment 'sideways' (expected 'top', 'middle', 'bottom', 'justify', or 'distributed')",
    ),
  )
}

///|
test "load rejects a fill that is empty or not a color-or-mapping" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { fill: { } } }\n",
    ),
    Some("spec.yaml: cell 'A1' fill needs a 'color'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { fill: [red] } }\n",
    ),
    Some("spec.yaml: cell 'A1' fill must be a hex color or a mapping"),
  )
}

///|
test "load rejects malformed borders and border edges" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { border: 3 } }\n",
    ),
    Some("spec.yaml: cell 'A1' border must be a style name or a mapping"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { border: { left: { color: \"FF0000\" } } } }\n",
    ),
    Some("spec.yaml: cell 'A1' border needs a 'style'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: { border: { left: 3 } } }\n",
    ),
    Some("spec.yaml: cell 'A1' border edge must be a style name or a mapping"),
  )
}

///|
test "load parses column/row default styles and the workbook default font" {
  let workbook = load_ok(
    (
      #|default_font: Calibri
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: B
      #|        style: { font: { bold: true } }
      #|      - at: D-F
      #|        format: "0.00"
      #|    rows:
      #|      - at: 1
      #|        style: { fill: "DDDDDD" }
      #|      - at: 2-3
      #|        style: { align: { horizontal: right } }
      #|
    ),
  )
  assert_eq(workbook.default_font, Some("Calibri"))
  let sheet = workbook.sheets[0]
  // Column B is bold; D-F share one number-format band.
  assert_eq(sheet.columns.length(), 2)
  assert_eq(sheet.columns[0].first, 2)
  assert_eq(sheet.columns[0].last, 2)
  assert_eq(sheet.columns[0].style.unwrap().font.unwrap().bold, Some(true))
  assert_eq(sheet.columns[1].first, 4)
  assert_eq(sheet.columns[1].last, 6)
  assert_eq(sheet.columns[1].style.unwrap().number_format, Some("0.00"))
  // Row 1 filled; rows 2-3 right-aligned as one band.
  assert_eq(sheet.rows.length(), 2)
  assert_eq((sheet.rows[0].first, sheet.rows[0].last), (1, 1))
  assert_eq((sheet.rows[1].first, sheet.rows[1].last), (2, 3))
  assert_eq(sheet.rows[1].style.unwrap().align.unwrap().horizontal, Some(Right))
}

///|
test "a named style is declared once and referenced by name from many cells" {
  let workbook = load_ok(
    (
      #|defs:
      #|  styles:
      #|    header: { font: { bold: true }, fill: "DDDDDD" }
      #|sheets:
      #|  - name: S
      #|    columns:
      #|      - at: A
      #|        style: header
      #|    cells:
      #|      A1: { value: "Name", style: header }
      #|      B1: { value: "Qty", style: header }
      #|
    ),
  )
  let sheet = workbook.sheets[0]
  let header : @model.Style = {
    ..@model.Style::empty(),
    font: Some({
      bold: Some(true),
      italic: None,
      underline: None,
      strike: None,
      size: None,
      name: None,
      color: None,
    }),
    fill: Some({ color: @units.Color::parse("DDDDDD").unwrap() }),
  }
  // Both cells and the column band resolve to the one declared style, so the
  // emitter interns them to a single cellXfs id (ADR-004).
  assert_eq(sheet.cells[0].style, Some(header))
  assert_eq(sheet.cells[1].style, Some(header))
  assert_eq(sheet.columns[0].style, Some(header))
}

///|
test "a style reference still layers a cell's own format on top" {
  let workbook = load_ok(
    (
      #|defs:
      #|  styles:
      #|    money: { font: { bold: true } }
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: 1.5, style: money, format: "0.00" }
      #|
    ),
  )
  let style = workbook.sheets[0].cells[0].style.unwrap()
  assert_eq(style.font.unwrap().bold, Some(true))
  assert_eq(style.number_format, Some("0.00"))
}

///|
test "a style extends another, overriding attribute by attribute" {
  let workbook = load_ok(
    (
      #|defs:
      #|  styles:
      #|    base:
      #|      font: { name: Calibri, size: 11, color: "111111" }
      #|      align: { horizontal: left, wrap: true }
      #|      border: { all: thin }
      #|    header:
      #|      extends: base
      #|      font: { bold: true, color: "FFFFFF" }
      #|      fill: "1F3864"
      #|      align: { horizontal: center }
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: x, style: header }
      #|      A2: { value: y, style: base }
      #|
    ),
  )
  let header = workbook.sheets[0].cells[0].style.unwrap()
  let font = header.font.unwrap()
  // Set by the child.
  assert_eq(font.bold, Some(true))
  assert_eq(font.color, @units.Color::parse("FFFFFF"))
  // Left alone by the child, so the base shows through — the merge reaches
  // inside the font rather than replacing it whole.
  assert_eq(font.name, Some("Calibri"))
  assert_eq(font.size, Some(11.0))
  // Same for alignment; `wrap` survives while `horizontal` is overridden.
  assert_eq(header.align.unwrap().horizontal, Some(Center))
  assert_eq(header.align.unwrap().wrap, Some(true))
  // Borders come through untouched, and the child's own fill is added.
  assert_eq(header.borders.unwrap().left, Some({ style: Thin, color: None }))
  assert_eq(header.fill.unwrap().color, @units.Color::parse("1F3864").unwrap())
  // The base itself is unchanged by having been extended.
  let base = workbook.sheets[0].cells[1].style.unwrap()
  assert_eq(base.font.unwrap().bold, None)
  assert_eq(base.fill, None)
}

///|
test "extends resolves forward references and works on an inline style" {
  // `child` is declared before the `parent` it extends.
  let forward = load_ok(
    (
      #|defs:
      #|  styles:
      #|    child: { extends: parent, font: { bold: true } }
      #|    parent: { font: { size: 20 } }
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: x, style: child }
      #|
    ),
  )
  let font = forward.sheets[0].cells[0].style.unwrap().font.unwrap()
  assert_eq(font.bold, Some(true))
  assert_eq(font.size, Some(20.0))
  // A chain of three, and an inline style extending a declared one.
  let chain = load_ok(
    (
      #|defs:
      #|  styles:
      #|    a: { font: { name: Arial } }
      #|    b: { extends: a, font: { size: 9 } }
      #|    c: { extends: b, font: { italic: true } }
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: x, style: c }
      #|      A2: { value: y, style: { extends: a, font: { bold: true } } }
      #|
    ),
  )
  let deep = chain.sheets[0].cells[0].style.unwrap().font.unwrap()
  assert_eq(deep.name, Some("Arial"))
  assert_eq(deep.size, Some(9.0))
  assert_eq(deep.italic, Some(true))
  let inline = chain.sheets[0].cells[1].style.unwrap().font.unwrap()
  assert_eq(inline.name, Some("Arial"))
  assert_eq(inline.bold, Some(true))
}

///|
test "load rejects style inheritance cycles and a dangling extends" {
  assert_eq(
    schema_message(
      "defs:\n  styles:\n    a: { extends: b }\n    b: { extends: a }\nsheets:\n  - name: S\n",
    ),
    Some("spec.yaml: style inheritance cycle: a -> b -> a"),
  )
  // A style extending itself is the shortest cycle.
  assert_eq(
    schema_message(
      "defs:\n  styles:\n    a: { extends: a }\nsheets:\n  - name: S\n",
    ),
    Some("spec.yaml: style inheritance cycle: a -> a"),
  )
  assert_eq(
    schema_message(
      "defs:\n  styles:\n    a: { extends: nope }\nsheets:\n  - name: S\n",
    ),
    Some("spec.yaml: style 'a' extends undefined style 'nope'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: x, style: { extends: nope } }\n",
    ),
    Some("spec.yaml: cell 'A1' extends undefined style 'nope'"),
  )
}

///|
test "load accepts a fill and border shorthand" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: { value: 1, style: { fill: { color: "00FF00" }, border: medium } }
      #|
    ),
  )
  let style = workbook.sheets[0].cells[0].style.unwrap()
  assert_eq(style.fill, Some({ color: @units.Color::parse("00FF00").unwrap() }))
  assert_eq(
    style.borders,
    Some({
      left: Some({ style: Medium, color: None }),
      right: Some({ style: Medium, color: None }),
      top: Some({ style: Medium, color: None }),
      bottom: Some({ style: Medium, color: None }),
    }),
  )
}

///|
test "load rejects references to undefined names" {
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { value: 1, style: ghost }\n",
    ),
    Some("spec.yaml: cell 'A1' references undefined style 'ghost'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { $ref: missing }\n",
    ),
    Some("spec.yaml: cell 'A1' references undefined value 'missing'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    cells:\n      A1: { formula: { $ref: nope } }\n",
    ),
    Some("spec.yaml: cell 'A1' references undefined formula 'nope'"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    columns:\n      - at: A\n        style: gone\n",
    ),
    Some("spec.yaml: column 'A' references undefined style 'gone'"),
  )
}
