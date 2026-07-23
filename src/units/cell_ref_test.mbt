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
test "CellRef::parse_a1 accepts valid references and inverts to_a1" {
  assert_eq(
    @units.CellRef::parse_a1("A1"),
    Some(@units.CellRef::new(col=1, row=1)),
  )
  assert_eq(
    @units.CellRef::parse_a1("AA10"),
    Some(@units.CellRef::new(col=27, row=10)),
  )
  assert_eq(
    @units.CellRef::parse_a1("AAA100"),
    Some(@units.CellRef::new(col=703, row=100)),
  )
  // Round-trips with to_a1.
  let r = @units.CellRef::new(col=52, row=7)
  assert_eq(@units.CellRef::parse_a1(r.to_a1()), Some(r))
}

///|
test "CellRef::parse_a1 rejects malformed references" {
  assert_eq(@units.CellRef::parse_a1(""), None)
  assert_eq(@units.CellRef::parse_a1("A"), None) // no row
  assert_eq(@units.CellRef::parse_a1("1"), None) // no column
  assert_eq(@units.CellRef::parse_a1("A0"), None) // row must be >= 1
  assert_eq(@units.CellRef::parse_a1("1A"), None) // digits before letters
  assert_eq(@units.CellRef::parse_a1("A1B"), None) // trailing letters
  assert_eq(@units.CellRef::parse_a1("a1"), None) // lowercase not accepted
}

///|
test "CellRef stores column and row and compares by value" {
  let a = @units.CellRef::new(col=3, row=7)
  assert_eq(a.col, 3)
  assert_eq(a.row, 7)
  assert_eq(a, @units.CellRef::new(col=3, row=7))
  assert_not_eq(a, @units.CellRef::new(col=7, row=3))
}
