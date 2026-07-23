///|
test "parse_column maps labels to 1-based indices (inverse of the column half of to_a1)" {
  assert_eq(@units.parse_column("A"), Some(1))
  assert_eq(@units.parse_column("Z"), Some(26))
  assert_eq(@units.parse_column("AA"), Some(27))
  assert_eq(@units.parse_column("AAA"), Some(703))
  // Not a bare label: empty, lowercase, or containing digits.
  assert_eq(@units.parse_column(""), None)
  assert_eq(@units.parse_column("a"), None)
  assert_eq(@units.parse_column("A1"), None)
}

///|
test "parse_uint reads a non-negative digit run, rejecting empty or non-digit" {
  assert_eq(@units.parse_uint("0"), Some(0))
  assert_eq(@units.parse_uint("42"), Some(42))
  assert_eq(@units.parse_uint(""), None)
  assert_eq(@units.parse_uint("1a"), None)
}

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
