///|
fn main raise {
  let dtype : @h5.DataType = Compound(16, [
    { name: "id", offset: 0, datatype: Unsigned(8, Big), },
    {
      name: "quality",
      offset: 8,
      datatype: EnumType(Unsigned(1, Little), [
        ("OK", b"\x01"),
        ("MISSING", b"\x00"),
      ]),
    },
    {
      name: "samples",
      offset: 10,
      datatype: ArrayType([2], Signed(2, Little)),
    },
  ])
  let raw = b"\xff\xff\xff\xff\xff\xff\xff\xff\x01\x00\x01\x00\xfe\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x03\x00\x04\x00\x00\x00"
  let value = @h5.ArrayValue::new(dtype, Simple([2]), raw)
  let doc = @h5.Document::new()
  doc.add_dataset(
    "/observations",
    value,
    chunked=Some(
      @h5.ChunkOptions::new([1], gzip=Some(6), shuffle=true, fletcher32=true),
    ),
  )
  doc.set_attribute("/observations", "example", value.element(0))
  let file = @h5.H5File::open(doc.encode())
  let restored = file.read("/observations")
  assert_eq(restored.bytes(), raw)
  assert_eq(restored.field("id").unsigned_at(0), 0xffffffffffffffffUL)
  assert_eq(restored.field("quality").enum_name_at(0), Some("OK"))
  assert_eq(restored.field("samples").expand_array().signed_at(1), -2L)
  assert_eq(file.chunks("/observations").length(), 2)
  println(
    "Typed scientific records, fixed-array samples and enum quality survive compressed HDF5 exchange",
  )
}
