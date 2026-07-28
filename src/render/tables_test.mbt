// Tests for the one inference in `render` that *moves* something out of the
// spec: a block of plain values becomes a file beside it. Which regions qualify
// matters more than how the CSV is punctuated — a wrong "yes" silently changes
// a workbook, where a wrong "no" only leaves a long `cells:` block.

///|
/// A sheet of `rows` × `columns` plain values, filled from `A1`.
fn literal_sheet(rows : Int, columns : Int) -> @model.Workbook {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("Sales")
  for row in 1..<=rows {
    for col in 1..<=columns {
      sheet.set(@units.CellRef::new(col~, row~), Text("r\{row}c\{col}"))
    }
  }
  wb
}

///|
test "a block of plain values becomes a table beside the spec" {
  let wb = literal_sheet(@render.min_csv_rows, @render.min_csv_columns)
  let tables = @render.data_tables(wb)
  assert_eq(tables.length(), 1)
  assert_eq(tables[0].sheet, "Sales")
  assert_eq(tables[0].at.to_a1(), "A1")
  assert_eq(tables[0].path, "data/sales.csv")
  // Every cell it covers leaves the `cells:` block, which is the point.
  assert_eq(
    tables[0].covered.length(),
    @render.min_csv_rows * @render.min_csv_columns,
  )
}

///|
test "a block too small to be worth a file stays in the spec" {
  for
    wb in [
      literal_sheet(@render.min_csv_rows - 1, @render.min_csv_columns),
      literal_sheet(@render.min_csv_rows, @render.min_csv_columns - 1),
    ] {
    assert_eq(@render.data_tables(wb).length(), 0)
  }
}

///|
test "a styled cell anywhere in the region keeps the whole region inline" {
  let wb = literal_sheet(@render.min_csv_rows, @render.min_csv_columns)
  // `data:` carries no formatting (`docs/spec.md` §9), so moving a styled cell
  // into one would drop the style without saying so.
  wb.sheets[0].set(@units.CellRef::new(col=1, row=1), Text("Title"), style={
    ..@model.Style::empty(),
    font: Some({ ..@model.Font::empty(), bold: Some(true) }),
  })
  assert_eq(@render.data_tables(wb).length(), 0)
}

///|
test "a formula anywhere in the region keeps it inline" {
  let wb = literal_sheet(@render.min_csv_rows, @render.min_csv_columns)
  wb.sheets[0].set(
    @units.CellRef::new(col=1, row=1),
    Formula(formula="1+1", cached=None),
  )
  assert_eq(@render.data_tables(wb).length(), 0)
}

///|
test "a ragged region stays inline: a CSV cannot say which field was missing" {
  let wb = literal_sheet(@render.min_csv_rows, @render.min_csv_columns)
  // One more cell out to the right makes the rectangle bigger than what is
  // filled, so the rows would no longer all be the same length.
  wb.sheets[0].set(
    @units.CellRef::new(col=@render.min_csv_columns + 3, row=1),
    Text("stray"),
  )
  assert_eq(@render.data_tables(wb).length(), 0)
}

///|
test "two sheets get two files, and their names do not collide" {
  let wb = @model.Workbook::new()
  for name in ["Sales", "sales"] {
    let sheet = wb.add_sheet(name)
    for row in 1..<=@render.min_csv_rows {
      for col in 1..<=@render.min_csv_columns {
        sheet.set(@units.CellRef::new(col~, row~), Number(row.to_double()))
      }
    }
  }
  let tables = @render.data_tables(wb)
  assert_eq(tables.length(), 2)
  // Both sheets flatten to the same file name — the flattening lowercases, so
  // `Sales` and `sales` land on one — and the second is numbered.
  assert_eq(tables[0].path, "data/sales.csv")
  assert_eq(tables[1].path, "data/sales_2.csv")
}

///|
test "a sheet name that is not a file name becomes one" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("Q3 Sales (final)")
  for row in 1..<=@render.min_csv_rows {
    for col in 1..<=@render.min_csv_columns {
      sheet.set(@units.CellRef::new(col~, row~), Number(1.0))
    }
  }
  assert_eq(@render.data_tables(wb)[0].path, "data/q3_sales__final_.csv")
}

///|
test "text that would read back as another type is quoted" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  // The loader reads a *bare* CSV field as the scalar it looks like, so each of
  // these has to be quoted to come back as the text it is.
  let tricky = ["007", "true", "false", "1,200", "he said \"hi\"", "-5", ".5"]
  for row, text in tricky {
    sheet.set(@units.CellRef::new(col=1, row=row + 1), Text(text))
    sheet.set(@units.CellRef::new(col=2, row=row + 1), Number(1.0))
  }
  // Pad to the size that earns a file.
  for row in tricky.length()..<@render.min_csv_rows {
    sheet.set(@units.CellRef::new(col=1, row=row + 1), Text("plain"))
    sheet.set(@units.CellRef::new(col=2, row=row + 1), Number(1.0))
  }
  let csv = @render.data_tables(wb)[0].csv
  inspect(
    csv,
    content=(
      #|"007",1
      #|"true",1
      #|"false",1
      #|"1,200",1
      #|"he said ""hi""",1
      #|"-5",1
      #|".5",1
      #|plain,1
      #|
    ),
  )
}

///|
test "a number goes out as a number and a boolean as a boolean" {
  let wb = @model.Workbook::new()
  let sheet = wb.add_sheet("S")
  for row in 1..<=@render.min_csv_rows {
    sheet.set(@units.CellRef::new(col=1, row~), Number(row.to_double()))
    sheet.set(@units.CellRef::new(col=2, row~), Bool(row % 2 == 0))
  }
  let lines = @render.data_tables(wb)[0].csv.split("\n").collect()
  // A whole number keeps no fraction, so the field reads as the integer it is.
  assert_eq(lines[0].to_owned(), "1,false")
  assert_eq(lines[1].to_owned(), "2,true")
}

///|
test "an empty sheet contributes no table" {
  let wb = @model.Workbook::new()
  wb.add_sheet("Empty") |> ignore
  assert_eq(@render.data_tables(wb).length(), 0)
}
