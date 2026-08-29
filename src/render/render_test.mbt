///|
/// A one-sheet workbook, plus the sheet.
fn fixture() -> (@model.Workbook, @model.Sheet) {
  let wb = @model.Workbook()
  (wb, wb.add_sheet("S"))
}

///|
fn at(reference : String) -> @units.CellRef {
  @units.CellRef::parse_a1(reference).unwrap()
}

///|
/// A style setting only a number format.
fn formatted(code : String) -> @model.Style {
  { ..@model.Style::empty(), number_format: Some(code), }
}

///|
/// A style setting only bold.
fn bold() -> @model.Style {
  {
    ..@model.Style::empty(),
    font: Some({ ..@model.Font::empty(), bold: Some(true), }),
  }
}

///|
/// A bold style on a fill — the one combination that reads as a heading.
fn header_style() -> @model.Style {
  { ..bold(), fill: Some({ color: @units.Color::parse("1F3864").unwrap(), }), }
}

///|
/// The rendered spec as text, which is what a reader would see.
fn spec(wb : @model.Workbook) -> String {
  @yaml.write(@render.workbook(wb))
}

///|
test "a plain sheet of values renders as the shorthand" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.set(at("B1"), Number(2400000.0))
  sheet.set(at("C1"), Bool(true))
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: Region
      #|      B1: 2400000
      #|      C1: true
      #|
    ),
  )
}

///|
test "cells come out in reading order, whatever order they were set in" {
  let (wb, sheet) = fixture()
  sheet.set(at("B2"), Text("d"))
  sheet.set(at("A1"), Text("a"))
  sheet.set(at("B1"), Text("b"))
  sheet.set(at("A2"), Text("c"))
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: a
      #|      B1: b
      #|      A2: c
      #|      B2: d
      #|
    ),
  )
}

///|
test "a whole number renders as an integer, not as a float" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(2400000.0))
  sheet.set(at("A2"), Number(0.085))
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: 2400000
      #|      A2: 0.085
      #|
    ),
  )
}

///|
test "a style worn twice is declared and named; one worn once is inlined" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"), style=header_style())
  sheet.set(at("B1"), Text("Revenue"), style=header_style())
  sheet.set(at("A2"), Text("APAC"), style=bold())
  inspect(
    spec(wb),
    content=(
      #|defs:
      #|  styles:
      #|    header:
      #|      font:
      #|        bold: true
      #|      fill: "1F3864"
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1:
      #|        value: Region
      #|        style: header
      #|      B1:
      #|        value: Revenue
      #|        style: header
      #|      A2:
      #|        value: APAC
      #|        style:
      #|          font:
      #|            bold: true
      #|
    ),
  )
}

///|
test "a shared format-only style is named for what it formats" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(1.0), style=formatted("0.0%"))
  sheet.set(at("A2"), Number(2.0), style=formatted("0.0%"))
  sheet.set(at("B1"), Number(3.0), style=formatted("#,##0"))
  sheet.set(at("B2"), Number(4.0), style=formatted("#,##0"))
  let written = spec(wb)
  assert_true(written.contains("percent:\n      format: \"0.0%\""))
  assert_true(written.contains("number:\n      format: \"#,##0\""))
}

///|
test "a format worn once goes out as the bare shorthand, not as a style" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(0.085), style=formatted("0.0%"))
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1:
      #|        value: 0.085
      #|        format: "0.0%"
      #|
    ),
  )
}

///|
test "a blank cell renders as its styling alone" {
  // The one cell shape with nothing under `value:` — what a shaded box or a
  // ruled table edge comes out as. The loader reads this form back, so the two
  // sides have to agree on it.
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.set(at("B1"), Blank, style=formatted("0.0%"))
  sheet.set(at("C1"), Blank, style=bold())
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: Region
      #|      B1:
      #|        format: "0.0%"
      #|      C1:
      #|        style:
      #|          font:
      #|            bold: true
      #|
    ),
  )
}

///|
test "names collide into a numbered suffix rather than overwriting" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(1.0), style=formatted("0%"))
  sheet.set(at("A2"), Number(2.0), style=formatted("0%"))
  sheet.set(at("B1"), Number(3.0), style=formatted("0.00%"))
  sheet.set(at("B2"), Number(4.0), style=formatted("0.00%"))
  let written = spec(wb)
  assert_true(written.contains("percent:"))
  assert_true(written.contains("percent_2:"))
}

///|
test "a look with nothing to say for itself gets a neutral name" {
  let (wb, sheet) = fixture()
  let odd : @model.Style = {
    ..@model.Style::empty(),
    align: Some({ horizontal: Some(Right), vertical: None, wrap: None, }),
  }
  sheet.set(at("A1"), Text("a"), style=odd)
  sheet.set(at("A2"), Text("b"), style=odd)
  assert_true(spec(wb).contains("style:\n      align:"))
}

///|
test "a formula range renders as one entry, not as its cells" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(1.0))
  sheet.add_formula({
    at: { top_left: at("C1"), bottom_right: at("C9"), },
    formula: "A1*2",
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: 1
      #|    formulas:
      #|      - at: C1:C9
      #|        formula: A1*2
      #|
    ),
  )
}

///|
test "the layout keys render, and a band's span reads as Excel writes it" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_column_band(first=2, last=3, width=12.0)
  sheet.set_row_band(first=1, last=1, height=28.0)
  sheet.merge(at("A1"), at("C1"))
  sheet.set_panes(Freeze(at("A3")))
  sheet.set_gridlines(false)
  sheet.set_tab_color(@units.Color::parse("1F77B4").unwrap())
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: x
      #|    columns:
      #|      - at: B-C
      #|        width: 12
      #|    rows:
      #|      - at: "1"
      #|        height: 28
      #|    merges:
      #|      - A1:C1
      #|    freeze: A3
      #|    gridlines: false
      #|    tab_color: "1F77B4"
      #|
    ),
  )
}

///|
test "a hidden sheet and the active tab render" {
  let wb = @model.Workbook()
  wb.add_sheet("Summary").set(at("A1"), Text("x"))
  wb.add_sheet("Scratch", visibility=Hidden) |> ignore
  wb.set_active_sheet("Summary")
  inspect(
    spec(wb),
    content=(
      #|active: Summary
      #|sheets:
      #|  - name: Summary
      #|    cells:
      #|      A1: x
      #|  - name: Scratch
      #|    visibility: hidden
      #|
    ),
  )
}

///|
test "rich text renders its runs, plain ones as bare strings" {
  let (wb, sheet) = fixture()
  sheet.set(
    at("A1"),
    RichText([
      { text: "plain ", font: None, },
      {
        text: "bold",
        font: Some({ ..@model.Font::empty(), bold: Some(true), }),
      },
    ]),
  )
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1:
      #|        rich:
      #|          - "plain "
      #|          - text: bold
      #|            font:
      #|              bold: true
      #|
    ),
  )
}

///|
test "the decorations render in the schema's own vocabulary" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("x"))
  sheet.set_filter({ top_left: at("A1"), bottom_right: at("C1"), })
  sheet.add_validation({
    at: { top_left: at("B2"), bottom_right: at("B9"), },
    rule: List(["Draft", "Sent"]),
    allow_blank: false,
    prompt: None,
    error: None,
  })
  sheet.add_validation({
    at: { top_left: at("C2"), bottom_right: at("C9"), },
    rule: Compare(kind=TextLength, check=AtMost(Number(12.0))),
    allow_blank: true,
    prompt: None,
    error: None,
  })
  sheet.add_link(at("A1"), Url("https://example.com"))
  sheet.add_comment(at("A1"), "a note")
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: x
      #|    filter: A1:C1
      #|    validations:
      #|      - at: B2:B9
      #|        list:
      #|          - Draft
      #|          - Sent
      #|        allow_blank: false
      #|      - at: C2:C9
      #|        text_length:
      #|          at_most: 12
      #|    links:
      #|      A1: https://example.com
      #|    comments:
      #|      A1: a note
      #|
    ),
  )
}

///|
test "a table renders only the toggles that differ from Excel's defaults" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Text("Region"))
  sheet.add_table({
    at: { top_left: at("A1"), bottom_right: at("B2"), },
    name: Some("Sales"),
    style: None,
    banded_rows: true,
    banded_columns: false,
    first_column: true,
    last_column: false,
  })
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1: Region
      #|    tables:
      #|      - at: A1:B2
      #|        name: Sales
      #|        first_column: true
      #|
    ),
  )
}

///|
/// A style that only takes attributes away.
fn clears(attrs : Array[@model.StyleAttr]) -> @model.Style {
  @model.Style::empty().clearing(@model.StyleAttrs::of(attrs))
}

///|
test "a cleared attribute is written as null, beside the ones that are set" {
  let (wb, sheet) = fixture()
  sheet.set_column_band(first=1, last=1, style=header_style())
  sheet.set(
    at("A1"),
    Text("APAC"),
    style=(
        {
          ..@model.Style::empty(),
          font: Some({ ..@model.Font::empty(), italic: Some(true), }),
        } : @model.Style)
      .clearing(@model.StyleAttrs::of([Fill]))
      .clearing(@model.StyleAttrs::of([FontBold])),
  )
  inspect(
    spec(wb),
    content=(
      #|sheets:
      #|  - name: S
      #|    cells:
      #|      A1:
      #|        value: APAC
      #|        style:
      #|          font:
      #|            italic: true
      #|            bold: null
      #|          fill: null
      #|    columns:
      #|      - at: A
      #|        style:
      #|          font:
      #|            bold: true
      #|          fill: "1F3864"
      #|
    ),
  )
}

///|
test "a style that only clears a format is a style, not the format shorthand" {
  let (wb, sheet) = fixture()
  sheet.set(at("A1"), Number(1.0), style=clears([NumberFormat]))
  assert_true(spec(wb).contains("style:\n          format: null"))
}

///|
test "Picture::key separates an anchored picture from the sheet background" {
  let at = @units.CellRef(col=2, row=3)
  assert_eq(@render.Picture::key("Sales", Some(at)), "Sales!B3")
  assert_eq(@render.Picture::key("Sales", None), "Sales!background")
  // The background and a picture anchored on the same sheet must not collide,
  // or one would overwrite the other's file.
  assert_true(
    @render.Picture::key("Sales", Some(at)) !=
    @render.Picture::key("Sales", None),
  )
}
