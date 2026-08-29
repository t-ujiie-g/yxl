///|
/// The sole shape a spec loads.
fn loaded_shape(body : String) -> @model.Shape raise {
  let shapes = load_ok(sheet_spec("    shapes:\n" + body)).sheets[0].shapes
  assert_eq(shapes.length(), 1)
  shapes[0]
}

///|
test "a shape loads its anchor and geometry, leaving the rest to defaults" {
  let shape = loaded_shape("      - at: B2\n        kind: rectangle\n")
  assert_eq(shape.at.to_a1(), "B2")
  assert_eq(shape.preset, "rect")
  assert_eq(shape.text, None)
  assert_eq(shape.width, None)
  assert_eq(shape.height, None)
  assert_eq(shape.fill, None)
  assert_eq(shape.line_color, None)
  assert_eq(shape.line_width, None)
  assert_eq(shape.alt_text, None)
  assert_eq(shape.positioning, Move)
}

///|
test "a shape loads its text, size, colours, alt text, and positioning" {
  let shape = loaded_shape(
    (
      #|      - at: D2
      #|        kind: cloud
      #|        text: Approved
      #|        size: { width: 240, height: 120 }
      #|        fill: "1F77B4"
      #|        line: { color: "333333", width: 2.5 }
      #|        alt: An approval stamp
      #|        positioning: fixed
      #|
    ),
  )
  assert_eq(shape.preset, "cloud")
  assert_eq(shape.text, Some(@model.Plain("Approved")))
  assert_eq(shape.width, Some(240))
  assert_eq(shape.height, Some(120))
  assert_eq(shape.fill.unwrap().hex(), "1F77B4")
  assert_eq(shape.line_color.unwrap().hex(), "333333")
  assert_eq(shape.line_width, Some(2.5))
  assert_eq(shape.alt_text, Some("An approval stamp"))
  assert_eq(shape.positioning, Fixed)
}

///|
test "a shape's line takes a bare hex shorthand, width left to the theme" {
  let shape = loaded_shape(
    "      - at: B2\n        kind: rectangle\n        line: \"FF0000\"\n",
  )
  assert_eq(shape.line_color.unwrap().hex(), "FF0000")
  assert_eq(shape.line_width, None)
}

///|
test "a shape's text takes lines, each written as a cell's rich run is" {
  let shape = loaded_shape(
    (
      #|      - at: B2
      #|        kind: rectangle
      #|        text:
      #|          - plain
      #|          - { text: loud, font: { bold: true } }
      #|
    ),
  )
  guard shape.text is Some(Lines(lines)) else { fail("expected text lines") }
  assert_eq(lines.length(), 2)
  assert_eq(lines[0], { text: "plain", font: None, })
  assert_eq(lines[1].text, "loud")
  assert_eq(lines[1].font.unwrap().bold, Some(true))
}

///|
test "a geometry the backend would corrupt is refused with the reason" {
  assert_eq(
    schema_message(
      sheet_spec("    shapes:\n      - at: B2\n        kind: arrow_right\n"),
    ),
    Some(
      "spec.yaml: shape at 'B2' asks for 'arrow_right', whose DrawingML token 'rightArrow' the Excel backend lowercases into one Excel does not recognize — pick a geometry whose token has no capitals, or wait for the upstream fix",
    ),
  )
}

///|
test "no accepted geometry carries a capital, so every token survives" {
  // The backend lowercases `prst` on the way out; the accepted table must
  // never contain a token that trip would corrupt.
  for preset in @model.shape_presets {
    let (_, token) = preset
    assert_eq(token, token.to_lower())
  }
}

///|
test "every spec preset maps to a distinct DrawingML token" {
  let seen_names = []
  let seen_tokens = []
  for preset in @model.shape_presets {
    let (name, token) = preset
    assert_false(seen_names.contains(name))
    assert_false(seen_tokens.contains(token))
    seen_names.push(name)
    seen_tokens.push(token)
    let shape = loaded_shape("      - at: B2\n        kind: \{name}\n")
    assert_eq(shape.preset, token)
  }
}

///|
test "a shape needs its anchor and its geometry" {
  assert_eq(
    schema_message(sheet_spec("    shapes:\n      - kind: rectangle\n")),
    Some("spec.yaml: a shape is missing required key 'at'"),
  )
  assert_eq(
    schema_message(sheet_spec("    shapes:\n      - at: B2\n")),
    Some("spec.yaml: shape at 'B2' is missing required key 'kind'"),
  )
}

///|
test "an unknown geometry is a diagnostic naming the accepted ones" {
  guard schema_message(
      sheet_spec("    shapes:\n      - at: B2\n        kind: dodecahedron\n"),
    )
    is Some(message) else {
    fail("expected a diagnostic")
  }
  assert_true(
    message.has_prefix(
      "spec.yaml: unknown shape kind 'dodecahedron' in shape at 'B2'",
    ),
  )
  assert_true(message.contains("'chevron'"))
}

///|
test "a shape rejects an unknown key" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        macro: Beep\n",
      ),
    ),
    Some(
      "spec.yaml: unknown key 'macro' in shape at 'B2' (expected 'at', 'kind', 'text', 'size', 'fill', 'line', 'alt', or 'positioning')",
    ),
  )
}

///|
test "a shape's size needs both dimensions, each whole and positive" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        size: { width: 240 }\n",
      ),
    ),
    Some("spec.yaml: shape at 'B2' 'size' needs both 'width' and 'height'"),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        size: { width: 0, height: 100 }\n",
      ),
    ),
    Some(
      "spec.yaml: shape at 'B2' 'size' 'width' must be between 1 and 20000 pixels, not 0",
    ),
  )
}

///|
test "a shape's line rejects a missing color, a flat width, and a structure" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        line: { width: 2 }\n",
      ),
    ),
    Some("spec.yaml: shape at 'B2' 'line' needs a 'color'"),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        line: { color: \"333333\", width: 0 }\n",
      ),
    ),
    Some(
      "spec.yaml: shape at 'B2' 'line' 'width' must be above 0 (points), not 0",
    ),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        line: [3]\n",
      ),
    ),
    Some("spec.yaml: shape at 'B2' 'line' must be a hex color or a mapping"),
  )
}

///|
test "a shape's text must be text or lines, and lines may not be empty" {
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        text: { boom: 1 }\n",
      ),
    ),
    Some("spec.yaml: shape at 'B2' 'text' must be text or a sequence of lines"),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        text: []\n",
      ),
    ),
    Some("spec.yaml: shape at 'B2' 'text' needs at least one line"),
  )
  assert_eq(
    schema_message(
      sheet_spec(
        "    shapes:\n      - at: B2\n        kind: rectangle\n        text: [[1]]\n",
      ),
    ),
    Some("spec.yaml: shape at 'B2' rich text run must be text or a mapping"),
  )
}
