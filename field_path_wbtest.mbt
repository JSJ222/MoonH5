///|
fn nested_records() -> ArrayValue raise H5Error {
  let dtype : DataType = Compound(6, [
    {
      name: "outer",
      offset: 1,
      datatype: Compound(4, [
        { name: "reading", offset: 1, datatype: Unsigned(2, Big), },
      ]),
    },
  ])
  ArrayValue::new(
    dtype,
    Simple([2]),
    b"\xff\xff\x01\x02\xff\xff\xee\xee\x02\x03\xee\xee",
  )
}

///|
test "nested projection composes compound offsets and preserves endianness" {
  let projected = nested_records().field_path(["outer", "reading"])
  assert_eq(projected.unsigned_at(0), 258UL)
  assert_eq(projected.unsigned_at(1), 515UL)
  assert_eq(projected.dataspace(), Simple([2]))
}
