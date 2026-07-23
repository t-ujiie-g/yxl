///|
test "CellRef::to_a1 encodes single-letter columns" {
  assert_eq(@units.CellRef::new(col=1, row=1).to_a1(), "A1")
  assert_eq(@units.CellRef::new(col=26, row=10).to_a1(), "Z10")
}

///|
test "CellRef::to_a1 encodes multi-letter columns (bijective base-26)" {
  assert_eq(@units.CellRef::new(col=27, row=1).to_a1(), "AA1")
  assert_eq(@units.CellRef::new(col=52, row=3).to_a1(), "AZ3")
  assert_eq(@units.CellRef::new(col=703, row=100).to_a1(), "AAA100")
}

///|
test "CellRef stores column and row and compares by value" {
  let a = @units.CellRef::new(col=3, row=7)
  assert_eq(a.col, 3)
  assert_eq(a.row, 7)
  assert_eq(a, @units.CellRef::new(col=3, row=7))
  assert_not_eq(a, @units.CellRef::new(col=7, row=3))
}
