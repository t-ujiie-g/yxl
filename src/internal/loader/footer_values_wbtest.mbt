///|
test "a criterion escapes the wildcards and quotes Excel would read" {
  assert_eq(group_criterion(Some(Text("A*B?~\"x\""))), "\"=A~*B~?~~\"\"x\"\"\"")
  assert_eq(group_criterion(Some(Number(7.0))), "7")
  assert_eq(group_criterion(Some(Number(1.5))), "1.5")
  assert_eq(group_criterion(None), "\"\"")
}

///|
test "group values sort numbers, then text, then a blank" {
  let values : Array[@model.CellValue?] = [
    None,
    Some(Text("b")),
    Some(Number(2.0)),
    Some(Text("a")),
    Some(Number(1.0)),
  ]
  values.sort_by(compare_group_values)
  assert_eq(values, [
    Some(Number(1.0)),
    Some(Number(2.0)),
    Some(Text("a")),
    Some(Text("b")),
    None,
  ])
}

///|
test "text sorts by code point, not by length or UTF-16 code unit" {
  let values : Array[@model.CellValue?] = [
    Some(Text("\u{10000}")),
    Some(Text("b")),
    Some(Text("\u{E000}")),
    Some(Text("aa")),
    Some(Text("a")),
  ]
  values.sort_by(compare_group_values)
  assert_eq(values, [
    Some(Text("a")),
    Some(Text("aa")),
    Some(Text("b")),
    Some(Text("\u{E000}")),
    Some(Text("\u{10000}")),
  ])
  assert_eq(compare_code_points("ab", "ab"), 0)
}
