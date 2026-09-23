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
