///|
/// Golden / round-trip test at the compile boundary: a model compiles to `.xlsx`
/// bytes, and re-opening those bytes with the backend's reader yields the cells
/// the model declared.
test "to_bytes round-trips a model through real .xlsx bytes" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("Sheet1")
  sheet.set(@units.CellRef::new(col=1, row=1), Text("yxl"))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(42.0))
  sheet.set(@units.CellRef::new(col=3, row=1), Bool(true))
  sheet.set(@units.CellRef::new(col=1, row=2), Text("second row"))
  let bytes = @emit.to_bytes(wb)

  // A valid .xlsx is a non-empty ZIP: check the local-file-header magic.
  assert_true(bytes.length() > 0)
  assert_eq(bytes[0], b'P')
  assert_eq(bytes[1], b'K')

  // Re-open and confirm the declared cells survived the round trip.
  let reopened = @xlsx.read(bytes[:])
  assert_eq(reopened.get_cell("Sheet1", "A1"), Some("yxl"))
  assert_eq(reopened.get_cell("Sheet1", "B1"), Some("42"))
  // The backend reads a boolean cell back as "1"/"0".
  assert_eq(reopened.get_cell("Sheet1", "C1"), Some("1"))
  assert_eq(reopened.get_cell("Sheet1", "A2"), Some("second row"))
}

///|
test "MbtexcelEmitter emits every sheet in order" {
  let wb = @model.Workbook::new()
  wb.add_sheet("First").set(@units.CellRef::new(col=1, row=1), Text("a"))
  wb.add_sheet("Second").set(@units.CellRef::new(col=1, row=1), Text("b"))
  let bytes = @emit.MbtexcelEmitter::new().emit(wb)
  let reopened = @xlsx.read(bytes[:])
  assert_eq(reopened.get_cell("First", "A1"), Some("a"))
  assert_eq(reopened.get_cell("Second", "A1"), Some("b"))
  // Declaration order is the tab order.
  assert_eq(reopened.sheet_index("First"), 0)
  assert_eq(reopened.sheet_index("Second"), 1)
}

///|
test "sheet visibility and the active sheet survive a round trip" {
  let wb = @model.Workbook::new()
  // The first sheet is hidden, so the backend must see every sheet before any
  // of them is hidden — otherwise no visible sheet would be left at that point.
  wb.add_sheet("Scratch", visibility=Hidden) |> ignore
  wb.add_sheet("Internals", visibility=VeryHidden) |> ignore
  wb.add_sheet("Summary") |> ignore
  wb.set_active_sheet("Summary")
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  assert_false(reopened.sheet_visible("Scratch"))
  assert_false(reopened.sheet_visible("Internals"))
  assert_true(reopened.sheet_visible("Summary"))
  // `activeTab` is an index into the sheet order.
  assert_eq(reopened.get_active_sheet_index(), 2)
}

///|
test "number formats are applied, and equal formats share one style id" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  sheet.set(@units.CellRef::new(col=1, row=1), Number(0.5), format="0.00%")
  sheet.set(@units.CellRef::new(col=2, row=1), Number(0.25), format="0.00%")
  sheet.set(
    @units.CellRef::new(col=3, row=1),
    Number(1234.5),
    format="#,##0.00",
  )
  sheet.set(@units.CellRef::new(col=4, row=1), Number(7.0))
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])

  // The format is really applied: the formatted read-back reflects it.
  assert_eq(reopened.get_cell_value("S", "A1", raw=false), Some("50.00%"))
  assert_eq(reopened.get_cell_value("S", "C1", raw=false), Some("1,234.50"))

  // Interning (ADR-004): equal format codes compile to one shared style id,
  // distinct codes to distinct ids, and an unformatted cell to the default.
  let percent = reopened.get_cell_style("S", "A1")
  assert_eq(reopened.get_cell_style("S", "B1"), percent)
  assert_not_eq(reopened.get_cell_style("S", "C1"), percent)
  assert_eq(reopened.get_cell_style("S", "D1"), Some(0))
}

///|
test "a full style round-trips its attributes and identical styles share one id" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  let style : @model.Style = {
    number_format: Some("0.00"),
    font: Some({
      bold: Some(true),
      italic: Some(true),
      underline: None,
      strike: None,
      size: Some(14.0),
      name: Some("Arial"),
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
      right: None,
      top: None,
      bottom: Some({ style: Double, color: @units.Color::parse("000000") }),
    }),
  }
  sheet.set(@units.CellRef::new(col=1, row=1), Number(1.5), style~)
  sheet.set(@units.CellRef::new(col=2, row=1), Number(2.5), style~)
  // The same look minus the font is a distinct style.
  sheet.set(@units.CellRef::new(col=3, row=1), Number(3.5), style={
    ..style,
    font: None,
  })
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])

  // Interning (ADR-004): identical styles share one id; a different style does not.
  let id = reopened.get_cell_style("S", "A1")
  assert_eq(reopened.get_cell_style("S", "B1"), id)
  assert_not_eq(reopened.get_cell_style("S", "C1"), id)

  // The emitted style really carries the declared attributes.
  let readback = reopened.get_style(id.unwrap())
  assert_eq(readback.font.unwrap().bold, Some(true))
  assert_eq(readback.font.unwrap().italic, Some(true))
  assert_eq(readback.alignment.unwrap().horizontal, Some("center"))
  assert_eq(readback.alignment.unwrap().vertical, Some("center"))
  // The number format still formats the value on read-back.
  assert_eq(reopened.get_cell_value("S", "A1", raw=false), Some("1.50"))
}

///|
test "column/row default styles emit and share the cell style cache; default font applies" {
  let wb = @model.Workbook::new(default_font="Arial")
  let sheet = wb.add_sheet("S")
  let bold : @model.Style = {
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
  }
  // A bold cell, then the same bold look as a whole-column and whole-row band.
  sheet.set(@units.CellRef::new(col=1, row=1), Text("x"), style=bold)
  sheet.set_column_band(first=2, last=3, style=bold)
  sheet.set_row_band(first=5, last=5, style=bold)
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])

  // The workbook default font took effect.
  assert_eq(reopened.get_default_font(), "Arial")

  // Interning (ADR-004): the cell, the columns, and the row all reuse one id.
  let id = reopened.get_cell_style("S", "A1")
  assert_true(id is Some(_) && id != Some(0))
  assert_eq(reopened.get_col_style("S", 2), id)
  assert_eq(reopened.get_col_style("S", 3), id)
  assert_eq(reopened.get_row_style("S", 5), id)
}

///|
test "merges, column widths, and row heights survive a round trip" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  sheet.set(@units.CellRef::new(col=1, row=1), Text("title"))
  // Corners given reversed; the model canonicalizes to A1:C1.
  sheet.merge(
    @units.CellRef::new(col=3, row=1),
    @units.CellRef::new(col=1, row=1),
  )
  sheet.set_column_band(first=2, last=2, width=18.0)
  sheet.set_row_band(first=1, last=1, height=24.0)
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  assert_eq(reopened.get_merge_cells("S"), ["A1:C1"])
  assert_eq(reopened.get_col_width("S", 2), Some(18.0))
  assert_eq(reopened.get_row_height("S", 1), Some(24.0))
  // The merged cell keeps the top-left value.
  assert_eq(reopened.get_cell("S", "A1"), Some("title"))
}

///|
test "hidden and grouped bands survive a round trip alongside their other properties" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  // A collapsed group: columns B-C are grouped one level deep and hidden, while
  // D keeps a width and stays visible at the outer level.
  sheet.set_column_band(first=2, last=3, hidden=true, outline_level=1)
  sheet.set_column_band(first=4, last=4, width=12.0, outline_level=1)
  sheet.set_row_band(first=2, last=3, hidden=true, outline_level=2)
  sheet.set_row_band(first=4, last=4, height=30.0, hidden=false)
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  assert_false(reopened.col_visible("S", 2))
  assert_false(reopened.col_visible("S", 3))
  assert_true(reopened.col_visible("S", 4))
  assert_eq(reopened.col_outline_level("S", 3), 1)
  assert_eq(reopened.col_outline_level("S", 4), 1)
  // The width on the grouped column is unaffected by the grouping.
  assert_eq(reopened.get_col_width("S", 4), Some(12.0))
  assert_false(reopened.row_visible("S", 2))
  assert_eq(reopened.row_outline_level("S", 2), 2)
  assert_true(reopened.row_visible("S", 4))
  assert_eq(reopened.get_row_height("S", 4), Some(30.0))
  // A column that no band touched keeps Excel's defaults.
  assert_true(reopened.col_visible("S", 1))
  assert_eq(reopened.col_outline_level("S", 1), 0)
}

///|
test "frozen panes, gridlines, and a tab color survive a round trip" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("Report")
  // Freezing at B2 keeps row 1 and column A in place.
  sheet.set_panes(Freeze(@units.CellRef::new(col=2, row=2)))
  sheet.set_gridlines(false)
  sheet.set_tab_color(@units.Color::parse("1F77B4").unwrap())
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  let panes = reopened.get_panes("Report")
  assert_true(panes.freeze)
  assert_false(panes.split)
  assert_eq(panes.x_split, 1)
  assert_eq(panes.y_split, 1)
  assert_eq(panes.top_left_cell, "B2")
  assert_eq(panes.active_pane, "bottomRight")
  assert_eq(reopened.get_sheet_view("Report", -1).show_grid_lines, Some(false))
  assert_eq(reopened.get_sheet_props("Report").tab_color_rgb, Some("1F77B4"))
}

///|
test "a split pane converts its point position to twips" {
  let wb = @model.Workbook::new()
  // 120 points across, unsplit vertically.
  wb.add_sheet("Wide").set_panes(Split(x=120.0, y=0.0))
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  let panes = reopened.get_panes("Wide")
  // A split pane carries no `state` attribute (ECMA-376 §18.18.52 defaults it to
  // "split"), and the backend's reader only recognizes the frozen state — so
  // `split` reads back false while the position and active pane survive.
  assert_false(panes.freeze)
  assert_eq(panes.x_split, 2400)
  assert_eq(panes.y_split, 0)
  assert_eq(panes.active_pane, "topRight")
}

///|
test "a date cell serializes to its Excel serial under the workbook's system" {
  let date = @units.DateTime::{
    year: 1900,
    month: 1,
    day: 1,
    hour: 0,
    minute: 0,
    second: 0,
  }
  // 1900 system: 1900-01-01 is serial 1.
  let wb1900 = @model.Workbook::new()
  wb1900.add_sheet("S").set(@units.CellRef::new(col=1, row=1), Date(date))
  let r1900 = @xlsx.read(@emit.to_bytes(wb1900)[:])
  assert_eq(r1900.get_cell_value("S", "A1", raw=true), Some("1"))

  // 1904 system: 1900-01-01 is 1460 real days before the 1904 epoch. (The
  // familiar "1462" offset between the systems only holds after Feb 1900, once
  // the 1900 leap-year bug applies.) The backend computes the same serial.
  let wb1904 = @model.Workbook::new(date_system=Date1904)
  wb1904.add_sheet("S").set(@units.CellRef::new(col=1, row=1), Date(date))
  let r1904 = @xlsx.read(@emit.to_bytes(wb1904)[:])
  assert_eq(r1904.get_cell_value("S", "A1", raw=true), Some("-1460"))
}

///|
test "a formula cell emits its formula and optional cached value" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  sheet.set(@units.CellRef::new(col=1, row=1), Number(3.0))
  sheet.set(@units.CellRef::new(col=2, row=1), Number(4.0))
  // A1+B1 with a cached result of 7.
  sheet.set(
    @units.CellRef::new(col=3, row=1),
    Formula(formula="A1+B1", cached=Some(Number(7.0))),
  )
  // A formula without a cached value.
  sheet.set(
    @units.CellRef::new(col=4, row=1),
    Formula(formula="A1*B1", cached=None),
  )
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  assert_eq(reopened.get_cell_formula("S", "C1"), Some("A1+B1"))
  assert_eq(reopened.get_cell_formula("S", "D1"), Some("A1*B1"))
  // The cached value is stored and read back raw.
  assert_eq(reopened.get_cell_value("S", "C1", raw=true), Some("7"))
}

///|
test "defined names emit and a reference cell resolves them via =name" {
  let wb = @model.Workbook::new()
  wb.add_defined_name("tax_rate", Number(0.08))
  wb.add_defined_name("company", Text("Acme Corp"))
  let sheet = wb.add_sheet("S")
  // A cell referencing the named value: the formula body is the name.
  sheet.set(
    @units.CellRef::new(col=1, row=1),
    Formula(formula="tax_rate", cached=Some(Number(0.08))),
  )
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])

  // The defined names survive with their refers_to expressions (a string
  // constant is quoted; a number is a bare literal).
  let names = reopened.get_defined_names()
  let by_name : Map[String, String] = Map([])
  for dn in names {
    by_name[dn.name] = dn.refers_to
  }
  assert_eq(by_name.get("tax_rate"), Some("0.08"))
  assert_eq(by_name.get("company"), Some("\"Acme Corp\""))

  // The reference cell emits `=tax_rate`; Excel resolves the name on open.
  assert_eq(reopened.get_cell_formula("S", "A1"), Some("tax_rate"))
  assert_eq(reopened.get_cell_value("S", "A1", raw=true), Some("0.08"))
}

///|
test "a rich-text cell round-trips its runs and per-run fonts" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  let bold_red : @model.Font = {
    bold: Some(true),
    italic: None,
    underline: None,
    strike: None,
    size: None,
    name: None,
    color: @units.Color::parse("FF0000"),
  }
  sheet.set(
    @units.CellRef::new(col=1, row=1),
    RichText([
      { text: "Plain ", font: None },
      { text: "bold red", font: Some(bold_red) },
    ]),
  )
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  // The concatenated text is what a plain read yields.
  assert_eq(reopened.get_cell("S", "A1"), Some("Plain bold red"))
  // The runs survive with their fonts.
  let runs = reopened.get_cell_rich_text("S", "A1").unwrap()
  assert_eq(runs.length(), 2)
  assert_eq(runs[0].text, "Plain ")
  assert_eq(runs[1].text, "bold red")
  assert_eq(runs[1].font.unwrap().bold, true)
  // The backend stores colors as ARGB, prepending an opaque alpha.
  assert_eq(runs[1].font.unwrap().color, Some("FFFF0000"))
}

///|
test "an error literal round-trips as the error text" {
  let wb = @model.Workbook::new()
  wb.add_sheet("S").set(@units.CellRef::new(col=1, row=1), Error("#DIV/0!"))
  let reopened = @xlsx.read(@emit.to_bytes(wb)[:])
  assert_eq(reopened.get_cell_value("S", "A1", raw=true), Some("#DIV/0!"))
}

///|
test "a backend failure surfaces as an EmitError, not a backend error" {
  // Two sheets with the same name make the backend reject the second one; the
  // seam must translate that into the pipeline's own error type.
  let wb = @model.Workbook::new()
  wb.add_sheet("Dup") |> ignore
  wb.add_sheet("Dup") |> ignore
  let caught = try {
    @emit.to_bytes(wb) |> ignore
    None
  } catch {
    @diag.EmitError(d) => Some(d.render())
  }
  assert_true(caught is Some(_))
}
