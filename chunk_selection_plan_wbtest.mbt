///|
test "chunk planning respects gaps between selected hyperslab blocks" {
  let data = ArrayValue::from_signed(
    Simple([8]),
    Array::makei(8, i => i.to_int64()),
  )
  let doc = Document::new()
  doc.add_dataset("/data", data)
  doc.set_chunking("/data", Some(ChunkOptions::new([2])))
  let file = H5File::open(doc.encode())
  let s = Selection::new(data.dataspace(), [
    { start: 0, stride: 6, count: 2, block: 1, },
  ])
  assert_eq(file.plan_chunks("/data", s).map(c => c.origin), [[0], [6]])
}
