///|
test "a fresh workbook has no sheets" {
  assert_eq(@model.Workbook().sheets.length(), 0)
}

///|
test "sheet finds a declared sheet by name and misses an undeclared one" {
  let wb = @model.Workbook()
  wb.add_sheet("Sales") |> ignore
  assert_eq(wb.sheet("Sales").unwrap().name, "Sales")
  assert_true(wb.sheet("Notes") is None)
}

///|
test "to_a1 writes a range as its unqualified corners" {
  let range : @model.CellRange = {
    top_left: @units.CellRef(col=1, row=1),
    bottom_right: @units.CellRef(col=4, row=10),
  }
  assert_eq(range.to_a1(), "A1:D10")
}

///|
test "add_sheet appends a sheet whose edits are visible in the workbook" {
  let wb = @model.Workbook()
  let sheet = wb.add_sheet("Sheet1")
  sheet.set(@units.CellRef(col=1, row=1), Text("yxl"))
  sheet.set(@units.CellRef(col=2, row=1), Number(42.0), format="0.00")
  assert_eq(wb.sheets.length(), 1)
  assert_eq(wb.sheets[0].name, "Sheet1")
  assert_eq(wb.sheets[0].cells.length(), 2)
  assert_eq(wb.sheets[0].cells[0], {
    pos: @units.CellRef(col=1, row=1),
    value: Text("yxl"),
    style: None,
  })
  assert_eq(wb.sheets[0].cells[1].value, Number(42.0))
  assert_eq(
    wb.sheets[0].cells[1].style,
    Some(@model.Style::number_format("0.00")),
  )
}

///|
test "set folds a format shorthand into a style, and merges with an explicit style" {
  let wb = @model.Workbook()
  let sheet = wb.add_sheet("S")
  let bold : @model.Style = {
    ..@model.Style::empty(),
    font: Some({ ..Font::empty(), bold: Some(true), }),
  }
  sheet.set(@units.CellRef(col=1, row=1), Number(1.0), format="0%")
  assert_eq(sheet.cells[0].style, Some(@model.Style::number_format("0%")))
  sheet.set(@units.CellRef(col=2, row=1), Number(1.0), format="0%", style=bold)
  assert_eq(sheet.cells[1].style, Some({ ..bold, number_format: Some("0%"), }))
  sheet.set(
    @units.CellRef(col=3, row=1),
    Number(1.0),
    style=@model.Style::empty(),
  )
  assert_eq(sheet.cells[2].style, None)
}

///|
test "Style::is_empty distinguishes the default style from any set attribute" {
  assert_true(@model.Style::empty().is_empty())
  assert_false(@model.Style::number_format("0.00").is_empty())
  assert_false(
    @model.Style::{ ..@model.Style::empty(), fill: Some({ color: red(), }), }.is_empty(),
  )
}

///|
test "Style::over keeps what the overriding style leaves unset" {
  let base : @model.Style = {
    ..@model.Style::empty(),
    font: Some({
      ..Font::empty(),
      bold: Some(false),
      size: Some(11.0),
      name: Some("Calibri"),
    }),
    fill: Some({ color: red(), }),
    borders: Some({
      left: Some({ style: Thin, color: None, }),
      right: None,
      top: None,
      bottom: None,
    }),
    align: Some({ horizontal: Some(Left), vertical: None, wrap: Some(true), }),
    number_format: Some("0.00"),
    protection: None,
  }
  let over : @model.Style = {
    ..@model.Style::empty(),
    font: Some({ ..Font::empty(), bold: Some(true), }),
    align: Some({ horizontal: Some(Center), vertical: None, wrap: None, }),
  }
  let merged = over.over(base)
  let font = merged.font.unwrap()
  assert_eq(font.bold, Some(true))
  assert_eq(font.size, Some(11.0))
  assert_eq(font.name, Some("Calibri"))
  assert_eq(merged.align.unwrap().horizontal, Some(Center))
  assert_eq(merged.align.unwrap().wrap, Some(true))
  assert_eq(merged.fill, base.fill)
  assert_eq(merged.borders, base.borders)
  assert_eq(merged.number_format, Some("0.00"))
  assert_eq(over.over(@model.Style::empty()), over)
  assert_eq(@model.Style::empty().over(base), base)
}

///|
/// A style that only takes attributes away.
fn clears(attrs : Array[@model.StyleAttr]) -> @model.Style {
  @model.Style::empty().clearing(@model.StyleAttrs::of(attrs))
}

///|
test "StyleAttrs is a set: membership, union, and difference" {
  let some = @model.StyleAttrs::of([Fill, FontBold])
  assert_true(some.has(Fill))
  assert_true(!some.has(FontItalic))
  assert_true(@model.StyleAttrs::none().is_empty())
  assert_true(!some.is_empty())
  assert_eq(
    some.adding(FontItalic),
    @model.StyleAttrs::of([Fill, FontBold, FontItalic]),
  )
  assert_eq(some.adding(Fill), some)
  assert_eq(
    some.union(@model.StyleAttrs::of([BorderTop])),
    @model.StyleAttrs::of([Fill, FontBold, BorderTop]),
  )
  assert_eq(
    some.except(@model.StyleAttrs::of([FontBold, BorderTop])),
    @model.StyleAttrs::of([Fill]),
  )
}

///|
test "an overriding style takes away the attribute it clears" {
  let base : @model.Style = {
    ..@model.Style::empty(),
    fill: Some({ color: red(), }),
    number_format: Some("0.00"),
    font: Some({ ..Font::empty(), bold: Some(true), size: Some(11.0), }),
  }
  let over = clears([Fill, FontSize])
  let merged = over.over(base)
  assert_eq(merged.fill, None)
  assert_eq(merged.number_format, Some("0.00"))
  assert_eq(merged.font.unwrap().bold, Some(true))
  assert_eq(merged.font.unwrap().size, None)
}

///|
test "a cleared attribute stays cleared until something sets it" {
  let column : @model.Style = {
    ..@model.Style::empty(),
    fill: Some({ color: red(), }),
  }
  let row = clears([Fill])
  let cell : @model.Style = {
    ..@model.Style::empty(),
    font: Some({ ..Font::empty(), bold: Some(true), }),
  }
  let layered = cell.over(row.over(column))
  assert_eq(layered.fill, None)
  assert_true(layered.cleared.has(Fill))
  let refilled = (
    { ..@model.Style::empty(), fill: Some({ color: red(), }), } : @model.Style).over(
    layered,
  )
  assert_eq(refilled.fill, Some({ color: red(), }))
  assert_true(!refilled.cleared.has(Fill))
}

///|
test "an attribute this style sets cannot also be cleared" {
  let style = (
    {
      ..@model.Style::empty(),
      fill: Some({ color: red(), }),
      font: Some({ ..Font::empty(), bold: Some(true), }),
    } : @model.Style).clearing(@model.StyleAttrs::of([Fill, FontSize]))
  assert_eq(style.fill, Some({ color: red(), }))
  assert_eq(style.assigned(), @model.StyleAttrs::of([Fill, FontBold]))
  assert_eq(style.cleared, @model.StyleAttrs::of([FontSize]))
}

///|
test "a style that only clears is not the empty style" {
  let style = clears([Fill])
  assert_true(!style.is_empty())
  assert_true(style.settled().is_empty())
}

///|
test "settling drops the record so one look interns once" {
  let plain : @model.Style = {
    ..@model.Style::empty(),
    font: Some({ ..Font::empty(), bold: Some(true), }),
  }
  let arrived_by_clearing = (
    {
      ..@model.Style::empty(),
      font: Some({ ..Font::empty(), bold: Some(true), }),
    } : @model.Style).clearing(@model.StyleAttrs::of([Fill]))
  assert_true(plain != arrived_by_clearing)
  assert_eq(plain, arrived_by_clearing.settled())
}

///|
test "a band style reaches a position from the column with the row over it" {
  let sheet = @model.Sheet("S")
  sheet.set_column_band(first=3, last=3, style={
    ..@model.Style::empty(),
    fill: Some({ color: red(), }),
  })
  sheet.set_row_band(first=2, last=2, style=clears([Fill]))
  let filled = sheet.band_style_at(@units.CellRef(col=3, row=1)).unwrap()
  assert_eq(filled.fill, Some({ color: red(), }))
  let cleared = sheet.band_style_at(@units.CellRef(col=3, row=2)).unwrap()
  assert_eq(cleared.fill, None)
  assert_true(sheet.band_style_at(@units.CellRef(col=1, row=1)) is None)
}

///|
test "a band's number format is not inherited by a text cell" {
  let banded = @model.Style::number_format("#,##0")
  assert_eq(banded.inherited_by(Number(1.0)).number_format, Some("#,##0"))
  assert_eq(banded.inherited_by(Text("Revenue")).number_format, None)
  // Four sections, and the fourth governs text, so this one does reach it.
  let with_text = @model.Style::number_format("#,##0;-#,##0;0;@")
  assert_eq(
    with_text.inherited_by(Text("Revenue")).number_format,
    Some("#,##0;-#,##0;0;@"),
  )
}

///|
test "band setters record an inclusive span and only the properties given" {
  let sheet = @model.Sheet("S")
  sheet.set_column_band(first=2, last=4, width=12.0, hidden=true)
  sheet.set_row_band(first=1, last=1, height=24.0, outline_level=2)
  assert_eq(sheet.columns, [
    {
      first: 2,
      last: 4,
      style: None,
      size: Some(12.0),
      hidden: Some(true),
      outline_level: None,
    },
  ])
  assert_eq(sheet.rows, [
    {
      first: 1,
      last: 1,
      style: None,
      size: Some(24.0),
      hidden: None,
      outline_level: Some(2),
    },
  ])
  // A band that sets nothing is still a band; dropping empties is the loader's
  // job, not the model's.
  sheet.set_column_band(first=9, last=9)
  assert_eq(sheet.columns.length(), 2)
}

///|
test "merge canonicalizes its corners whichever pair is given" {
  let sheet = @model.Sheet("S")
  sheet.merge(@units.CellRef(col=3, row=3), @units.CellRef(col=1, row=1))
  sheet.merge(@units.CellRef(col=3, row=1), @units.CellRef(col=1, row=3))
  let expected : @model.CellRange = {
    top_left: @units.CellRef(col=1, row=1),
    bottom_right: @units.CellRef(col=3, row=3),
  }
  assert_eq(sheet.merges, [expected, expected])
}

///|
test "sheet presentation setters are independent and default to Excel's own" {
  let sheet = @model.Sheet("S")
  assert_eq(sheet.visibility, Visible)
  assert_eq(sheet.panes, None)
  assert_eq(sheet.gridlines, None)
  assert_eq(sheet.tab_color, None)
  assert_eq(sheet.page, None)
  sheet.set_panes(Freeze(@units.CellRef(col=2, row=2)))
  sheet.set_gridlines(false)
  sheet.set_tab_color(red())
  sheet.set_page_setup({
    ..@model.PageSetup::empty(),
    orientation: Some(Landscape),
  })
  assert_eq(sheet.panes, Some(Freeze(@units.CellRef(col=2, row=2))))
  assert_eq(sheet.gridlines, Some(false))
  assert_eq(sheet.tab_color, Some(red()))
  assert_eq(sheet.page.unwrap().orientation, Some(Landscape))
  assert_eq(@model.Sheet("H", visibility=VeryHidden).visibility, VeryHidden)
}

///|
test "PageSetup::empty changes nothing" {
  let page = @model.PageSetup::empty()
  assert_eq(page.area, None)
  assert_eq(page.orientation, None)
  assert_eq(page.margins, None)
  assert_eq(page.scale, None)
  assert_eq(page.header, None)
  assert_eq(page.footer, None)
  assert_eq(page.breaks, [])
}

///|
test "defined names and the active sheet are workbook-wide, in declaration order" {
  let wb = @model.Workbook()
  assert_eq(wb.active_sheet, None)
  wb.add_defined_name("tax_rate", Number(0.08))
  wb.add_defined_name("company", Text("Acme"))
  assert_eq(wb.defined_names, [
    { name: "tax_rate", refers_to: Number(0.08), },
    { name: "company", refers_to: Text("Acme"), },
  ])
  wb.add_sheet("S") |> ignore
  wb.set_active_sheet("S")
  assert_eq(wb.active_sheet, Some("S"))
}

///|
test "overrides are workbook-wide, in declaration order, and read back per sheet" {
  let wb = @model.Workbook()
  let at = @units.CellRef(col=1, row=1)
  for name in ["First", "Second"] {
    wb.add_sheet(name) |> ignore
    wb.add_override({
      sheet: name,
      at,
      value: Some(Text(name)),
      style: None,
      reason: Some("by hand"),
    })
  }
  assert_eq(wb.overrides.map(entry => entry.sheet), ["First", "Second"])
  assert_eq(wb.sheet_overrides("Second").map(entry => entry.value), [
    Some(Text("Second")),
  ])
  assert_eq(wb.sheet_overrides("Third"), [])
}

///|
/// A color for the tests that need one; `parse` is exercised in `units`.
fn red() -> @units.Color {
  @units.Color::parse("FF0000").unwrap()
}

///|
test "cells keep insertion order across multiple sheets" {
  let wb = @model.Workbook()
  let s1 = wb.add_sheet("First")
  let s2 = wb.add_sheet("Second")
  s2.set(@units.CellRef(col=1, row=1), Text("b"))
  s1.set(@units.CellRef(col=1, row=1), Text("a"))
  assert_eq(wb.sheets.map(s => s.name), ["First", "Second"])
  assert_eq(wb.sheets[0].cells[0].value, Text("a"))
  assert_eq(wb.sheets[1].cells[0].value, Text("b"))
}

///|
test "CellRange::parse is the inverse of to_a1, in either corner order" {
  for text in ["A1:B9", "B9:A1", "A1:A1", "AA10:ZZ100"] {
    let parsed = @model.CellRange::parse(text)
    assert_true(parsed is Some(_))
    guard parsed is Some(range) else { return }
    assert_eq(@model.CellRange::parse(range.to_a1()), Some(range))
  }
  assert_eq(@model.CellRange::parse("A1:B9").unwrap().to_a1(), "A1:B9")
  assert_eq(@model.CellRange::parse("B9:A1").unwrap().to_a1(), "A1:B9")
}

///|
test "CellRange::parse refuses what is not two references around a colon" {
  for text in ["A1", "", ":", "A1:", ":B9", "A1:B9:C1", "1:9", "A0:B9", "x:y"] {
    assert_eq((text, @model.CellRange::parse(text)), (text, None))
  }
}

///|
test "parse_loose takes a single cell as the one-cell range it stands for" {
  // Excel writes a validation or conditional format over one cell as a bare
  // reference, which is the reason this variant exists.
  let single = @model.CellRange::parse_loose("C3")
  assert_true(single is Some(_))
  guard single is Some(range) else { return }
  assert_eq(range.top_left.to_a1(), "C3")
  assert_eq(range.bottom_right.to_a1(), "C3")
  assert_eq(@model.CellRange::parse_loose("A1:B9").unwrap().to_a1(), "A1:B9")
  assert_eq(@model.CellRange::parse_loose("nonsense"), None)
}

///|
test "Font::empty sets nothing, and says so" {
  let font = @model.Font::empty()
  assert_true(font.is_empty())
  assert_eq(font.bold, None)
  assert_eq(font.color, None)
  assert_true(!{ ..@model.Font::empty(), bold: Some(true), }.is_empty())
  // Two empty fonts are equal, which is what lets a style holding one intern
  // with a style holding none.
  assert_eq(@model.Font::empty(), @model.Font::empty())
}

///|
test "split_sheet_prefix follows Excel's quoting" {
  assert_eq(@model.split_sheet_prefix("A1:B9"), Some((None, "A1:B9")))
  assert_eq(
    @model.split_sheet_prefix("Lists!A1:A9"),
    Some((Some("Lists"), "A1:A9")),
  )
  assert_eq(
    @model.split_sheet_prefix("'Q3 data'!A1:A9"),
    Some((Some("Q3 data"), "A1:A9")),
  )
  // `''` is one apostrophe: the case a plain quote-strip would rename.
  assert_eq(
    @model.split_sheet_prefix("'It''s data'!A1:A3"),
    Some((Some("It's data"), "A1:A3")),
  )
  assert_eq(
    @model.split_sheet_prefix("'O''Brien'!A1"),
    Some((Some("O'Brien"), "A1")),
  )
  // An unquoted name splits at the first `!`, as Excel requires quotes around
  // any name that could be read as something else.
  assert_eq(
    @model.split_sheet_prefix("Sheet1!$A$1"),
    Some((Some("Sheet1"), "$A$1")),
  )
  assert_eq(@model.split_sheet_prefix("'Lists!A1:A3"), None)
  assert_eq(@model.split_sheet_prefix("'Lists'A1:A3"), None)
  assert_eq(@model.split_sheet_prefix("'Lists'"), None)
}
