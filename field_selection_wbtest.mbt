///|
test "hyperslab field reads agree with selecting whole records first" {
  let source = nested_records()
  let doc = Document::new()
  doc.add_dataset("/data", source)
  let s = Selection::new(source.dataspace(), [
    { start: 1, stride: 1, count: 1, block: 1, },
  ])
  let file = H5File::open(doc.encode())
  let result = file.read_field_selection("/data", s, ["outer", "reading"])
  assert_eq(
    result.bytes(),
    source.select(s).field_path(["outer", "reading"]).bytes(),
  )
  assert_eq(result.unsigned_at(0), 515UL)
}
