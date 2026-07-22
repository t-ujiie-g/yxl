// Phase 0 smoke test: prove the toolchain end to end — the `bobzhang/mbtexcel`
// backend builds a workbook and emits `.xlsx` bytes on the native target. The
// real compiler pipeline arrives in later phases behind the emitter seam.

///|
test "mbtexcel backend emits xlsx bytes" {
  let workbook = @xlsx.Workbook::new()
  let _ = workbook.new_sheet("Sheet1")
  workbook.set_cell_str("Sheet1", "A1", "yxl")
  let bytes = @xlsx.write(workbook)
  // A valid .xlsx is a non-empty ZIP; check the local-file-header magic "PK\x03\x04".
  assert_true(bytes.length() > 0)
  assert_eq(bytes[0], b'P')
  assert_eq(bytes[1], b'K')
}
