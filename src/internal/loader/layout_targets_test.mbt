///|
test "an override by meaning must find exactly one row" {
  let refused = (at : String) => {
    schema_message(named_spec("overrides:\n  - at: \{at}\n    value: 1\n"))
  }
  assert_eq(
    refused("{ layout: 店舗, column: cy, where: { branch: 東京 } }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' 'where' matches 2 rows of the data; it must find exactly one",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: cy, where: { branch: 福岡 } }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' 'where' matches 0 rows of the data; it must find exactly one",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: cy, where: { ratio: 0 } }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' 'where' names 'ratio', which is not a column the layout's data fills",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: cy, row: 4 }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' 'row' is 4, but the body has rows 1 to 3",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: cy }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' needs exactly one of 'where', 'row', 'header', 'footer', or 'title' to find its cell",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, column: sales, row: 1 }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' names column 'sales', which the layout does not have",
    ),
  )
  assert_eq(
    refused("{ layout: 支店, column: cy, row: 1 }"),
    Some(
      "spec.yaml: override 'at' names layout '支店', which no layout is called (named: '店舗')",
    ),
  )
  assert_eq(
    refused("{ layout: 店舗, row: 1 }"),
    Some(
      "spec.yaml: override 'at' on layout '店舗' needs a 'column' to go with its 'row'",
    ),
  )
}

///|
test "an override written before the sheets still finds a layout" {
  let source =
    #|overrides:
    #|  - at: { layout: t, column: a, row: 1 }
    #|    value: 2
    #|sheets:
    #|  - name: S
    #|    layouts:
    #|      - { at: A1, name: t, rows: 1, columns: [{ name: a }] }
    #|    cells:
    #|      A1: 1
    #|
  assert_eq(load_ok(source).overrides[0].at.to_a1(), "A1")
}

///|
test "an override may name a header, footer or title cell by meaning" {
  let at = target => {
    load_ok(
      sheet_keys_spec("overrides:\n  - at: " + target + "\n    value: x\n"),
    ).overrides[0].at.to_a1()
  }
  assert_eq(at("{ layout: t, column: v, header: 1 }"), "C3")
  assert_eq(at("{ layout: t, column: v, header: 2 }"), "C4")
  assert_eq(at("{ layout: t, column: key, header: 1 }"), "B3")
  assert_eq(at("{ layout: t, column: v, footer: 1 }"), "C7")
  assert_eq(at("{ layout: t, column: v, footer: last }"), "C7")
  let titled = load_ok(
    (
      #|sheets:
      #|  - name: S
      #|    layouts:
      #|      - { at: A1, name: t, title: 表, rows: 1, columns: [{ name: a }, { name: b }] }
      #|overrides:
      #|  - at: { layout: t, title: true }
      #|    value: 新しい表
      #|
    ),
  )
  assert_eq(titled.overrides[0].at.to_a1(), "A1")
}

///|
test "a layout cell by meaning refuses a covered cell and a part the layout lacks" {
  let refused = target => {
    schema_message(
      sheet_keys_spec("overrides:\n  - at: " + target + "\n    value: x\n"),
    )
  }
  assert_eq(
    refused("{ layout: t, column: key, header: 2 }"),
    Some(
      "spec.yaml: override 'at' on layout 't' lands inside the merged cells 'B3:B4'; name their first cell",
    ),
  )
  assert_eq(
    refused("{ layout: t, column: v, footer: 2 }"),
    Some(
      "spec.yaml: override 'at' on layout 't' 'footer' is 2, but the footer has rows 1 to 1",
    ),
  )
  assert_eq(
    refused("{ layout: t, column: v, header: top }"),
    Some(
      "spec.yaml: override 'at' on layout 't' 'header' must be a whole number: the header row, counting from 1",
    ),
  )
  assert_eq(
    refused("{ layout: t, title: true }"),
    Some(
      "spec.yaml: override 'at' on layout 't' names the title of a layout with none",
    ),
  )
  assert_eq(
    refused("{ layout: t, column: v, title: true }"),
    Some(
      "spec.yaml: override 'at' on layout 't' names a 'column' and the 'title', which spans them all",
    ),
  )
  assert_eq(
    refused("{ layout: t, column: v, row: 1, footer: 1 }"),
    Some(
      "spec.yaml: override 'at' on layout 't' needs exactly one of 'where', 'row', 'header', 'footer', or 'title' to find its cell",
    ),
  )
  assert_eq(
    schema_message(
      (
        #|sheets:
        #|  - name: S
        #|    layouts:
        #|      - { at: A1, name: t, rows: 1, columns: [{ name: a }] }
        #|    cells: { A1: 1 }
        #|overrides:
        #|  - { at: { layout: t, column: a, footer: last }, value: 2 }
        #|
      ),
    ),
    Some(
      "spec.yaml: override 'at' on layout 't' names the footer of a layout with none",
    ),
  )
}

///|
test "comments and links may be a list, at an A1 cell or a layout's cell" {
  let sheet = load_ok(
      sheet_keys_spec(
        (
          #|    comments:
          #|      - { at: { layout: t, column: v, where: { key: b } }, text: 確認中 }
          #|      - { at: A1, text: メモ, author: 経理 }
          #|    links:
          #|      - { at: { layout: t, column: key, footer: last }, url: "https://example.com" }
          #|      - { at: A2, to: "S!B3", tip: 一覧 }
          #|
        ),
      ),
    ).sheets[0]
  assert_eq(sheet.comments.map(c => (c.at.to_a1(), c.text, c.author)), [
    ("C6", "確認中", None),
    ("A1", "メモ", Some("経理")),
  ])
  assert_eq(sheet.links.map(link => (link.at.to_a1(), link.tip)), [
    ("B7", None),
    ("A2", Some("一覧")),
  ])
}

///|
test "a listed comment or link stays on its own sheet and keeps its own keys" {
  assert_eq(
    schema_message(
      sheet_keys_spec(
        "  - name: O\n    comments:\n      - { at: { layout: t, column: v, row: 1 }, text: x }\n",
      ),
    ),
    Some("spec.yaml: comment 'at' names a layout on sheet 'S', not this one"),
  )
  assert_eq(
    schema_message(
      sheet_keys_spec("    links:\n      - { url: \"https://e.com\" }\n"),
    ),
    Some("spec.yaml: a link is missing required key 'at'"),
  )
  assert_eq(
    schema_message(
      sheet_keys_spec("    comments:\n      - { at: A1, note: x }\n"),
    ),
    Some(
      "spec.yaml: unknown key 'note' in comment 'A1' (expected 'text' or 'author')",
    ),
  )
}

///|
test "a row band may name a layout's header, body or footer rows" {
  let sheet = load_ok(
      sheet_keys_spec(
        (
          #|    rows:
          #|      - { at: { layout: t, part: header }, height: 30 }
          #|      - { at: { layout: t, part: body }, group: 1 }
          #|      - { at: { layout: t, part: footer }, style: { font: { bold: true } } }
          #|
        ),
      ),
    ).sheets[0]
  assert_eq(sheet.rows.map(band => (band.first, band.last, band.size)), [
    (3, 4, Some(30.0)),
    (5, 6, None),
    (7, 7, None),
  ])
  assert_eq(sheet.rows[1].outline_level, Some(1))
}

///|
test "a row band names a part the layout has, on this sheet" {
  let refused = at => {
    schema_message(
      sheet_keys_spec("    rows:\n      - { at: " + at + ", height: 20 }\n"),
    )
  }
  assert_eq(
    refused("{ layout: t, part: title }"),
    Some("spec.yaml: row 'at' names the title of layout 't', which has none"),
  )
  assert_eq(
    refused("{ layout: t, part: totals }"),
    Some(
      "spec.yaml: unknown part 'totals' of layout 't' (expected 'title', 'header', 'body', or 'footer')",
    ),
  )
  assert_eq(
    refused("{ layout: t }"),
    Some("spec.yaml: row 'at' given by layout needs 'layout' and 'part'"),
  )
  assert_eq(
    refused("{ layout: u, part: body }"),
    Some("spec.yaml: row 'at' 'u' is not a named layout (layouts: 't')"),
  )
  assert_eq(
    schema_message(
      sheet_keys_spec(
        "  - name: O\n    rows:\n      - { at: { layout: t, part: body }, height: 20 }\n",
      ),
    ),
    Some("spec.yaml: row 'at' 't' names a layout on sheet 'S', not this one"),
  )
  assert_eq(
    refused("{ layout: t, part: body, gap: 1 }"),
    Some(
      "spec.yaml: unknown key 'gap' in row 'at' (expected 'layout' or 'part')",
    ),
  )
}
