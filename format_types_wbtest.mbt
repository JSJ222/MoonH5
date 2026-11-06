///|
fn record_fixture() -> ArrayValue raise H5Error {
  let dtype : DataType = Compound(24, [
    { name: "id", offset: 0, datatype: Unsigned(8, Big), },
    { name: "pair", offset: 8, datatype: ArrayType([2], Float(4, Little)), },
    {
      name: "state",
      offset: 16,
      datatype: EnumType(Unsigned(1, Little), [
        ("OFF", b"\x00"),
        ("ON", b"\x01"),
      ]),
    },
  ])
  let b = buffer()
  for i = 0; i < 15; i = i + 1 {
    for j = 7; j >= 0; j = j - 1 {
      b.u8(((0xffffffffffffffffUL - i.to_uint64()) >> (8 * j)).to_int() & 255)
    }
    b.uint(
      Float::from_double(i.to_double()).reinterpret_as_uint().to_uint64(),
      4,
    )
    b.uint(
      Float::from_double(-i.to_double()).reinterpret_as_uint().to_uint64(),
      4,
    )
    b.u8(i % 2)
    b.zeros(7)
  }
  ArrayValue::new(dtype, Simple([3, 5]), b.finish())
}

///|
test "structured types retain exact records nested arrays enum and independent type arrays" {
  let record = record_fixture()
  assert_eq(record.field("id").unsigned_at(0), 0xffffffffffffffffUL)
  assert_eq(record.field("pair").expand_array().dataspace(), Simple([3, 5, 2]))
  assert_eq(record.field("state").enum_name_at(1), Some("ON"))
  assert_eq(record.field("state").enum_base().unsigned_at(0), 0UL)
  let types = match record.datatype() {
    Compound(_, fields) => fields
    _ => fail("compound")
  }
  types.clear()
  assert_eq(record.field("id").unsigned_at(14), 0xfffffffffffffff1UL)
  let doc = Document::new()
  doc.add_dataset("/records", record)
  doc.set_attribute("/records", "sample", record.element(0))
  let f = H5File::open(doc.encode())
  assert_eq(f.read("/records").datatype(), record.datatype())
  assert_eq(f.read("/records").bytes(), record.bytes())
  assert_eq(
    f.attributes(path="/records")[0].value.field("state").enum_name_at(0),
    Some("OFF"),
  )
}

///|
test "chunked writer applies standard filters and supports clipped edge selection" {
  let record = record_fixture()
  for
    options in [
      ChunkOptions::new([2, 3]),
      ChunkOptions::new([2, 3], gzip=Some(6)),
      ChunkOptions::new([2, 3], gzip=Some(6), shuffle=true, fletcher32=true),
      ChunkOptions::new([2, 3], shuffle=true, fletcher32=true),
    ] {
    let doc = Document::new()
    doc.add_dataset("/records", record, chunked=Some(options))
    let bytes = doc.encode()
    assert_eq(bytes, doc.encode())
    let f = H5File::open(bytes)
    assert_eq(f.read("/records").bytes(), record.bytes())
    assert_eq(f.chunks("/records").length(), 4)
    let selection = Selection::new(record.space, [
      { start: 1, stride: 1, count: 2, block: 1, },
      { start: 2, stride: 2, count: 2, block: 1, },
    ])
    assert_eq(
      f.read_selection("/records", selection).bytes(),
      record.select(selection).bytes(),
    )
  }
}

///|
test "structured datatype and chunk options validate before document mutation" {
  for
    dtype in [
      Compound(4, [{ name: "x", offset: 3, datatype: Unsigned(2, Little), }]),
      Compound(4, [
        { name: "x", offset: 0, datatype: Unsigned(4, Little), },
        { name: "y", offset: 2, datatype: Unsigned(2, Little), },
      ]),
      ArrayType([0], Unsigned(1, Little)),
      EnumType(Float(4, Little), [("x", b"1234")]),
      EnumType(Unsigned(1, Little), [("x", b"\x01"), ("y", b"\x01")]),
    ] {
    assert_true(
      try {
        ignore(dtype.width())
        false
      } catch {
        _ => true
      },
    )
  }
  let a = ArrayValue::from_signed(Simple([2, 2]), [1L, 2L, 3L, 4L])
  let doc = Document::new()
  assert_true(
    try {
      doc.add_dataset(
        "/a",
        a,
        chunked=Some(ChunkOptions::new([0, 1], gzip=Some(6))),
      )
      false
    } catch {
      _ => true
    },
  )
  doc.add_dataset("/a", a)
  assert_true(
    try {
      doc.add_dataset(
        "/b",
        a,
        compact=true,
        chunked=Some(ChunkOptions::new([1, 1])),
      )
      false
    } catch {
      _ => true
    },
  )
  doc.add_dataset("/b", a)
  let source : Array[CompoundMember] = [
    { name: "x", offset: 0, datatype: Unsigned(1, Little), },
  ]
  let value = ArrayValue::new(Compound(1, source), Scalar, b"\x01")
  source.clear()
  assert_eq(value.field("x").unsigned_at(0), 1UL)
}

///|
test "datatype cycles budgets malformed encodings and chunk checksums fail explicitly" {
  let fields : Array[CompoundMember] = []
  let cyclic : DataType = Compound(1, fields)
  fields.push({ name: "loop", offset: 0, datatype: cyclic, })
  assert_true(
    try {
      ignore(cyclic.width())
      false
    } catch {
      _ => true
    },
  )
  let a = record_fixture()
  let doc = Document::new()
  doc.add_dataset(
    "/a",
    a,
    chunked=Some(
      ChunkOptions::new([2, 3], gzip=Some(1), shuffle=true, fletcher32=true),
    ),
  )
  let bytes = doc.encode()
  let file = H5File::open(bytes)
  let chunk = file.chunks("/a")[0]
  let broken = bytes.to_array()
  broken[chunk.address + chunk.stored_bytes - 1] = broken[chunk.address +
    chunk.stored_bytes -
    1] ^
    b'\x01'
  assert_true(
    try {
      ignore(H5File::open(Bytes::from_array(broken)).read("/a"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_type(cursor(b"\x36\x01\x00\x00\x01\x00\x00\x00\x78", 0, 9)))
      false
    } catch {
      _ => true
    },
  )
  let small = Document::new(limits={ ..Limits::default(), max_objects: 2, })
  assert_true(
    try {
      small.add_dataset("/x", a, chunked=Some(ChunkOptions::new([1, 1])))
      false
    } catch {
      _ => true
    },
  )
  let invalid = Document::new()
  assert_true(
    try {
      invalid.add_dataset(
        "/x",
        a,
        chunked=Some(ChunkOptions::new([2, 3], gzip=Some(10))),
      )
      false
    } catch {
      _ => true
    },
  )
  invalid.add_dataset("/x", a)
  invalid.set_chunking("/x", Some(ChunkOptions::new([2, 3], gzip=Some(0))))
  invalid.set_chunking("/x", None)
  assert_true(
    H5File::open(invalid.encode()).dataset_info("/x").storage
    is Contiguous(_, _),
  )
}
