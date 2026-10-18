///|
test "header levels merge a shared parent across and a short column down" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: A2
          #|        rows: 2
          #|        header_style: head
          #|        columns:
          #|          - { name: item, header: 部門 }
          #|          - { name: cy, header: [売上, 当年] }
          #|          - { name: py, header: [売上, 前年] }
          #|          - { name: ratio, header: [売上, 前年比], formula: "{{cy}}/{{py}}" }
        ),
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A2:A3", "B2:D2"])
  let cells = written(sheet)
  assert_eq(cells.get("A2"), Some((Text("部門"), true)))
  assert_eq(cells.get("A3"), Some((Blank, true)))
  assert_eq(cells.get("B2"), Some((Text("売上"), true)))
  assert_eq(cells.get("C2"), Some((Blank, true)))
  assert_eq(cells.get("D2"), Some((Blank, true)))
  assert_eq(cells.get("D3"), Some((Text("前年比"), true)))
  assert_eq(sheet.formulas[0].at.to_a1(), "D4:D5")
  assert_eq(sheet.formulas[0].formula, "B4/C4")
}

///|
test "a null level is a blank that merges with nothing" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: A1
          #|        rows: 1
          #|        header_style: head
          #|        columns:
          #|          - { name: item, header: [null, 部門] }
          #|          - { name: cy, header: [売上, 当年] }
          #|          - { name: py, header: [null, 前年] }
        ),
      ),
    ).sheets[0]
  assert_eq(merged(sheet), [])
  let cells = written(sheet)
  assert_eq(cells.get("A1"), Some((Blank, true)))
  assert_eq(cells.get("A2"), Some((Text("部門"), true)))
  assert_eq(cells.get("C1"), Some((Blank, true)))
  assert_eq(cells.get("C2"), Some((Text("前年"), true)))
}

///|
test "without a header style a blank writes no cell at all" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a, header: [X, a] }\n          - { name: b, header: [X, b] }\n          - { name: c, header: [null, c] }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A1:B1"])
  let cells = written(sheet)
  assert_eq(cells.get("B1"), None)
  assert_eq(cells.get("C1"), None)
  assert_eq(cells.get("A1"), Some((Text("X"), false)))
}

///|
test "the same label under different parents stays apart" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a, header: [売上, 当年] }\n          - { name: b, header: [粗利, 当年] }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), [])
}

///|
test "a level stretched down never also merges across" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns:\n          - { name: a, header: 備考 }\n          - { name: b, header: 備考 }\n          - { name: c, header: [X, c] }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A1:A2", "B1:B2"])
}

///|
test "a header cell's own style is laid over the header style" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_style: head\n        columns:\n          - { name: a, header: { value: A, style: weak } }\n",
      ),
    ).sheets[0]
  guard sheet.cells[0].style is Some(style) else { fail("unstyled header") }
  guard style.font is Some(font) else { fail("no font") }
  assert_eq(font.bold, Some(true))
  assert_true(font.color is Some(_))
}

///|
test "a header's levels are cells, and there is at least one" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, header: [] }]\n",
      ),
    ),
    Some("spec.yaml: layout 'A1' column 'a' header is an empty list"),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        columns: [{ name: a, header: [[x]] }]\n",
      ),
    ),
    Some("spec.yaml: layout 'A1' column 'a' header levels are cells, not lists"),
  )
}

///|
test "header_merge false writes the merged cells and no merge" {
  let sheet = load_ok(
      (
        #|defs:
        #|  styles:
        #|    head: { font: { bold: true } }
        #|    weak: { font: { color: "C00000" } }
        #|  blocks:
        #|    yoy:
        #|      columns:
        #|        - { name: cy, header: 当年 }
        #|        - { name: py, header: 前年 }
        #|sheets:
        #|  - name: 実績
        #|    layouts:
        #|      - at: A1
        #|        rows: 1
        #|        header_style: head
        #|        header_merge: false
        #|        columns:
        #|          - { name: item, header: 部門 }
        #|          - { block: yoy, as: sales, header: [{ value: 売上, style: weak }] }
        #|          - { name: note, header: [{ style: weak }, 備考] }
        #|          - { name: memo, header: [{ style: weak }, 備考] }
      ),
    ).sheets[0]
  assert_eq(merged(sheet), [])
  let cells = written(sheet)
  assert_eq(cells.get("A1"), Some((Text("部門"), true)))
  assert_eq(cells.get("A2"), Some((Blank, true)))
  assert_eq(cells.get("B1"), Some((Text("売上"), true)))
  assert_eq(cells.get("C1"), Some((Blank, true)))
  assert_eq(cells.get("C2"), Some((Text("前年"), true)))
  assert_eq(cells.get("D1"), Some((Blank, true)))
  assert_eq(cells.get("D2"), Some((Text("備考"), true)))
  assert_eq(cells.get("E2"), Some((Blank, true)))
}

///|
test "header_merge true is the default" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_merge: true\n        columns:\n          - { name: a, header: 備考 }\n          - { name: b, header: [X, b] }\n          - { name: c, header: [X, c] }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A1:A2", "B1:C1"])
}

///|
test "header_merge is a boolean, and needs a header to apply to" {
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_merge: no\n        columns: [{ name: a, header: A }]\n",
      ),
    ),
    Some("spec.yaml: layout 'A1' 'header_merge' must be true or false"),
  )
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_merge: false\n        columns: [{ name: a }]\n",
      ),
    ),
    Some(
      "spec.yaml: layout 'A1' has a 'header_merge' but no 'title' or column 'header' to merge",
    ),
  )
}

///|
/// Which border edges the cell at `reference` draws, as `"LRTB"` with `-` for
/// a missing edge, and which it clears.
fn edges(sheet : @model.Sheet, reference : String) -> (String, String) {
  for cell in sheet.cells {
    if cell.pos.to_a1() == reference {
      guard cell.style is Some(style) else { break }
      let borders = style.borders.unwrap_or(@model.Borders::empty())
      let drawn = [
        ("L", borders.left is Some(_)),
        ("R", borders.right is Some(_)),
        ("T", borders.top is Some(_)),
        ("B", borders.bottom is Some(_)),
      ]
      let cleared = [
        ("L", style.cleared.has(BorderLeft)),
        ("R", style.cleared.has(BorderRight)),
        ("T", style.cleared.has(BorderTop)),
        ("B", style.cleared.has(BorderBottom)),
      ]
      let show = (flags : Array[(String, Bool)]) => {
        flags.map(flag => if flag.1 { flag.0 } else { "-" }).join("")
      }
      return (show(drawn), show(cleared))
    }
  }
  ("none", "none")
}

///|
/// The header of #122: 部門 stretched down two rows beside 売上 over three.
fn outlined_header(merge : Bool) -> @model.Sheet raise {
  load_ok(
    layout_spec(
      "      - at: A1\n        rows: 1\n        header_style: { border: thin }\n        header_merge: \{merge}\n        columns:\n          - { name: item, header: 部門 }\n          - { name: cy, header: [売上, 当年] }\n          - { name: py, header: [売上, 前年] }\n          - { name: ratio, header: [売上, 前年比] }\n",
    ),
  ).sheets[0]
}

///|
test "a header without merges draws each span's outer border only" {
  let sheet = outlined_header(false)
  assert_eq(edges(sheet, "B1"), ("L-TB", "-R--"))
  assert_eq(edges(sheet, "C1"), ("--TB", "LR--"))
  assert_eq(edges(sheet, "D1"), ("-RTB", "L---"))
  assert_eq(edges(sheet, "A1"), ("LRT-", "---B"))
  assert_eq(edges(sheet, "A2"), ("LR-B", "--T-"))
  assert_eq(edges(sheet, "C2"), ("LRTB", "----"))
}

///|
test "a merged header keeps every edge, as Excel draws the merge's outline" {
  let sheet = outlined_header(true)
  assert_eq(edges(sheet, "C1"), ("LRTB", "----"))
  assert_eq(edges(sheet, "A2"), ("LRTB", "----"))
}

///|
test "a header without merges and without a border keeps its one style" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_style: { fill: \"DDEBF7\" }\n        header_merge: false\n        columns:\n          - { name: cy, header: [売上, 当年] }\n          - { name: py, header: [売上, 前年] }\n",
      ),
    ).sheets[0]
  let styles = sheet.cells
    .filter(cell => cell.pos.row == 1)
    .map(cell => cell.style)
  assert_eq(styles[0], styles[1])
  assert_eq(edges(sheet, "B1"), ("----", "----"))
}

///|
/// The style of the cell written at `reference`, by its font's boldness and
/// colour: `"bold"`, the colour's hex, or `"plain"`.
fn look(sheet : @model.Sheet, reference : String) -> String {
  for cell in sheet.cells {
    if cell.pos.to_a1() == reference {
      guard cell.style is Some({ font: Some(font), .. }) else { return "plain" }
      if font.bold is Some(true) {
        return "bold"
      }
      return font.color.map(color => color.hex()).unwrap_or("plain")
    }
  }
  "none"
}

///|
test "a header style list styles each row, a stretched cell by the row it starts" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: A1
          #|        rows: 1
          #|        header_style: [head, weak]
          #|        columns:
          #|          - { name: item, header: 部門 }
          #|          - { name: cy, header: [売上, 当年] }
          #|          - { name: py, header: [売上, 前年] }
          #|          - { name: note, header: [null, 備考] }
        ),
      ),
    ).sheets[0]
  assert_eq(look(sheet, "A1"), "bold")
  assert_eq(look(sheet, "A2"), "bold")
  assert_eq(look(sheet, "B1"), "bold")
  assert_eq(look(sheet, "C1"), "bold")
  assert_eq(look(sheet, "B2"), "C00000")
  assert_eq(look(sheet, "D1"), "bold")
  assert_eq(look(sheet, "D2"), "C00000")
}

///|
test "rows past a header style list wear its last style" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_style: [head, weak]\n        columns:\n          - { name: a, header: [x, y, z] }\n",
      ),
    ).sheets[0]
  assert_eq(look(sheet, "A1"), "bold")
  assert_eq(look(sheet, "A2"), "C00000")
  assert_eq(look(sheet, "A3"), "C00000")
}

///|
test "a header cell's own style lies over its row's style" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        rows: 1\n        header_style: [head, weak]\n        columns:\n          - { name: a, header: [x, { value: y, style: head }] }\n",
      ),
    ).sheets[0]
  guard sheet.cells[1].style is Some({ font: Some(font), .. }) else {
    fail("no font")
  }
  assert_eq(font.bold, Some(true))
  assert_eq(font.color.map(color => color.hex()), Some("C00000"))
}

///|
test "a header style list is not empty, nor longer than the header is deep" {
  let spec = style => {
    layout_spec(
      "      - at: A1\n        rows: 1\n        header_style: " +
      style +
      "\n        columns:\n          - { name: a, header: [x, y] }\n",
    )
  }
  assert_eq(
    schema_message(spec("[]")),
    Some("spec.yaml: layout 'A1' 'header_style' is an empty list"),
  )
  assert_eq(
    schema_message(spec("[head, weak, head]")),
    Some(
      "spec.yaml: layout 'A1' 'header_style' lists 3 styles, but the header is 2 rows deep",
    ),
  )
  assert_eq(
    schema_message(spec("[head, nope]")),
    Some(
      "spec.yaml: layout 'A1' header_style references undefined style 'nope'",
    ),
  )
}

///|
test "a title spans the layout's width above the header, merged" {
  let sheet = load_ok(
      layout_spec(
        (
          #|      - at: B2
          #|        name: t
          #|        title: { value: 店舗別実績, style: head }
          #|        values: [[a, 1]]
          #|        columns:
          #|          - { name: key, header: キー }
          #|          - { name: v, header: [値, 当年] }
          #|          - { name: w, header: [値, 前年] }
          #|
          #|    print: { area: t, titles: t }
          #|    freeze: { layout: t }
        ),
      ),
    ).sheets[0]
  assert_eq(merged(sheet).contains("B2:D2"), true)
  let cells = written(sheet)
  assert_eq(cells.get("B2"), Some((Text("店舗別実績"), true)))
  assert_eq(cells.get("D2"), Some((Blank, true)))
  assert_eq(cells.get("B3"), Some((Text("キー"), false)))
  assert_eq(cells.get("B5"), Some((Text("a"), false)))
  guard sheet.page is Some(page) else { fail("no print setup") }
  assert_eq(page.area.map(area => area.to_a1()), Some("B2:D5"))
  assert_eq(page.title_rows, Some({ first: 3, last: 4, }))
  assert_eq(sheet.panes, Some(Freeze(@units.CellRef::parse_a1("A5").unwrap())))
}

///|
test "a title without merges sits in the first cell, its inner edges dropped" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        title: { value: 実績, style: { border: thin } }\n        header_merge: false\n        rows: 1\n        columns:\n          - { name: a }\n          - { name: b }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), [])
  assert_eq(edges(sheet, "A1"), ("L-TB", "-R--"))
  assert_eq(edges(sheet, "B1"), ("-RTB", "L---"))
  assert_eq(written(sheet).get("A2"), None)
}

///|
test "a plain title writes no blanks, and a bad one is refused" {
  let sheet = load_ok(
      layout_spec(
        "      - at: A1\n        title: 実績\n        rows: 1\n        columns:\n          - { name: a }\n          - { name: b }\n",
      ),
    ).sheets[0]
  assert_eq(merged(sheet), ["A1:B1"])
  assert_eq(written(sheet).get("B1"), None)
  assert_eq(
    schema_message(
      layout_spec(
        "      - at: A1\n        title: [実績]\n        rows: 1\n        columns: [{ name: a }]\n",
      ),
    ),
    Some(
      "spec.yaml: cell 'layout 'A1' title' must be text, a number, or a boolean",
    ),
  )
}
