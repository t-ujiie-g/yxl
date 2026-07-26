// Sheet presentation: visibility, the active sheet, panes, gridlines, and the
// tab color (`loader.mbt`).

///|
test "load parses sheet visibility and the active sheet, keeping declaration order" {
  let workbook = load_ok(
    (
      #|active: Summary
      #|sheets:
      #|  - name: Data
      #|  - name: Summary
      #|  - name: Scratch
      #|    visibility: hidden
      #|  - name: Internals
      #|    visibility: very_hidden
      #|
    ),
  )
  // Sheet order is declaration order — the spec is the tab order.
  assert_eq(workbook.sheets.map(sheet => sheet.name), [
    "Data", "Summary", "Scratch", "Internals",
  ])
  assert_eq(workbook.sheets.map(sheet => sheet.visibility), [
    Visible,
    Visible,
    Hidden,
    VeryHidden,
  ])
  assert_eq(workbook.active_sheet, Some("Summary"))
  // Left out, `active` opens on the first sheet and every tab is visible.
  let plain = load_ok("sheets:\n  - name: S\n")
  assert_eq(plain.active_sheet, None)
  assert_eq(plain.sheets[0].visibility, Visible)
}

///|
test "load rejects a bad visibility, a dangling or hidden active sheet, and an all-hidden workbook" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    visibility: gone\n"),
    Some(
      "spec.yaml: unknown sheet visibility 'gone' (expected 'visible', 'hidden', or 'very_hidden')",
    ),
  )
  assert_eq(
    schema_message("active: Nope\nsheets:\n  - name: S\n"),
    Some("spec.yaml: active sheet 'Nope' is not a declared sheet"),
  )
  // Excel cannot open on a tab it does not show.
  assert_eq(
    schema_message(
      "active: S\nsheets:\n  - name: S\n    visibility: hidden\n  - name: T\n",
    ),
    Some("spec.yaml: active sheet 'S' is hidden"),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    visibility: hidden\n  - name: T\n    visibility: very_hidden\n",
    ),
    Some(
      "spec.yaml: every sheet is hidden; Excel needs at least one visible sheet",
    ),
  )
}

///|
test "load parses frozen and split panes, gridlines, and a tab color" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: Report
      #|    freeze: B2
      #|    gridlines: false
      #|    tab_color: "1F77B4"
      #|  - name: Wide
      #|    split: { x: 120 }
      #|
    ),
  )
  let report = workbook.sheets[0]
  assert_eq(report.panes, Some(Freeze(@units.CellRef::new(col=2, row=2))))
  assert_eq(report.gridlines, Some(false))
  assert_eq(report.tab_color, @units.Color::parse("1F77B4"))
  // An axis left out of `split` stays unsplit.
  assert_eq(workbook.sheets[1].panes, Some(Split(x=120.0, y=0.0)))
  // Left out, all three keep Excel's defaults.
  let plain = load_ok("sheets:\n  - name: S\n")
  assert_eq(plain.sheets[0].panes, None)
  assert_eq(plain.sheets[0].gridlines, None)
  assert_eq(plain.sheets[0].tab_color, None)
}

///|
test "load rejects a pointless or malformed freeze, split, and tab color" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    freeze: A1\n"),
    Some(
      "spec.yaml: 'freeze: A1' would freeze nothing (freeze at the first unfrozen cell)",
    ),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    freeze: B\n"),
    Some("spec.yaml: 'B' is not a valid A1 cell reference in 'freeze'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    split: { x: 0, y: 0 }\n"),
    Some("spec.yaml: sheet 'split' needs a non-zero 'x' or 'y' (in points)"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    split: { z: 1 }\n"),
    Some("spec.yaml: unknown key 'z' in sheet 'split' (expected 'x' or 'y')"),
  )
  // Excel's viewport is either frozen or split, not both.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    freeze: B2\n    split: { x: 1 }\n",
    ),
    Some("spec.yaml: sheet 'S' cannot combine 'freeze' and 'split'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    tab_color: nope\n"),
    Some("spec.yaml: sheet 'tab_color' is not a valid hex color: 'nope'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    gridlines: sometimes\n"),
    Some("spec.yaml: sheet 'gridlines' must be true or false"),
  )
}
