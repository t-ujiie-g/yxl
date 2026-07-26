// The per-sheet `print:` block (`page.mbt`).

///|
test "load parses a print block: area, orientation, margins, fit, header/footer, breaks" {
  let workbook = load_ok(
    (
      #|sheets:
      #|  - name: Report
      #|    print:
      #|      area: A1:D50
      #|      orientation: landscape
      #|      margins: { top: 1, bottom: 1, left: 0.7, right: 0.7 }
      #|      fit: { width: 1 }
      #|      header: "&CQuarterly report"
      #|      footer: "&LPage &P of &N"
      #|      breaks: [A21, C1]
      #|
    ),
  )
  let page = workbook.sheets[0].page.unwrap()
  assert_eq(
    page.area,
    Some({
      top_left: @units.CellRef::new(col=1, row=1),
      bottom_right: @units.CellRef::new(col=4, row=50),
    }),
  )
  assert_eq(page.orientation, Some(Landscape))
  assert_eq(
    page.margins,
    Some({
      top: Some(1.0),
      bottom: Some(1.0),
      left: Some(0.7),
      right: Some(0.7),
      header: None,
      footer: None,
    }),
  )
  // An axis left out of `fit` is unconstrained.
  assert_eq(page.scale, Some(Fit(width=1, height=0)))
  assert_eq(page.header, Some("&CQuarterly report"))
  assert_eq(page.footer, Some("&LPage &P of &N"))
  assert_eq(page.breaks, [
    @units.CellRef::new(col=1, row=21),
    @units.CellRef::new(col=3, row=1),
  ])
  // A percentage scale is the other half of Excel's scaling control.
  let scaled = load_ok("sheets:\n  - name: S\n    print: { scale: 80 }\n")
  assert_eq(scaled.sheets[0].page.unwrap().scale, Some(Percent(80)))
  // No `print:` block leaves Excel's defaults throughout.
  assert_eq(load_ok("sheets:\n  - name: S\n").sheets[0].page, None)
}

///|
test "load rejects out-of-range, contradictory, and malformed print settings" {
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { scale: 5 }\n"),
    Some("spec.yaml: print 'scale' must be between 10 and 400 percent"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { scale: 80.5 }\n"),
    Some("spec.yaml: print 'scale' must be a whole number of percent"),
  )
  // Excel scales by a percentage or by a page fit, never both.
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    print: { scale: 80, fit: { width: 1 } }\n",
    ),
    Some(
      "spec.yaml: sheet 'print' cannot combine 'scale' and 'fit' (Excel scales by one or the other)",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    print: { fit: { width: 0, height: 0 } }\n",
    ),
    Some(
      "spec.yaml: print 'fit' needs a non-zero 'width' or 'height' (in pages)",
    ),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { fit: { width: -1 } }\n"),
    Some(
      "spec.yaml: print 'fit' width must be a whole number of pages (0 for unconstrained)",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    print: { orientation: sideways }\n",
    ),
    Some(
      "spec.yaml: unknown print orientation 'sideways' (expected 'portrait' or 'landscape')",
    ),
  )
  assert_eq(
    schema_message(
      "sheets:\n  - name: S\n    print: { margins: { top: -1 } }\n",
    ),
    Some("spec.yaml: print margin 'top' cannot be negative"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { area: A1 }\n"),
    Some("spec.yaml: print area 'A1' must be 'TopLeft:BottomRight'"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { breaks: [A1] }\n"),
    Some("spec.yaml: a print break at 'A1' would break nothing"),
  )
  assert_eq(
    schema_message("sheets:\n  - name: S\n    print: { paper: a4 }\n"),
    Some(
      "spec.yaml: unknown key 'paper' in sheet 'print' (expected 'area', 'orientation', 'margins', 'scale', 'fit', 'header', 'footer', or 'breaks')",
    ),
  )
}
