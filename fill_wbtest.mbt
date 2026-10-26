///|
test "legacy fill values preserve exact bytes instead of silently becoming zero" {
  let encoded = message(4, b"\x02\x00\x00\x00\xf9\xff")
  assert_eq(decode_fill(encoded, 2), b"\xf9\xff")
  assert_eq(
    decode_fill(message(4, b"\x00\x00\x00\x00"), 4),
    b"\x00\x00\x00\x00",
  )
  assert_true(
    try {
      ignore(decode_fill(encoded, 4))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_fill(message(4, b"\x08\x00\x00\x00"), 8))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "dataspace ranks above the HDF5 maximum are rejected before serialization" {
  let impossible = { ..Limits::default(), max_rank: 33, }
  assert_true(
    try {
      ignore(Document::new(limits=impossible))
      false
    } catch {
      _ => true
    },
  )
  let rank32 = Simple(Array::make(32, 1))
  let value = ArrayValue::from_signed(rank32, [7L])
  let doc = Document::new()
  doc.add_dataset("/rank32", value)
  assert_eq(H5File::open(doc.encode()).read("/rank32").signed_at(0), 7L)
}
