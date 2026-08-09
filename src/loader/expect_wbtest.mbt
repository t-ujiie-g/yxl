///|
test "or_list joins one, two, and many spellings" {
  // Every enum table in the loader has three or more spellings, so the short
  // forms are only reachable from here — and they are what a two-valued key
  // added later would render through.
  assert_eq(or_list([]), "")
  assert_eq(or_list(["'left'"]), "'left'")
  assert_eq(or_list(["'left'", "'right'"]), "'left' or 'right'")
  assert_eq(
    or_list(["'left'", "'center'", "'right'"]),
    "'left', 'center', or 'right'",
  )
}
