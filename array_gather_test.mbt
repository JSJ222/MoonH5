///|
test "reshape and gather preserve UInt64 byte order duplicates and source arrays" {
  let a = @moonh5.ArrayValue::from_unsigned(Simple([2, 3]), [
    0UL, 1UL, 18446744073709551615UL, 3UL, 4UL, 5UL,
  ]).with_byte_order(Big)
  assert_eq(a.reshape(Simple([3, 2])).bytes(), a.bytes())
  let b = a.take_axis(1, [2, 0, 2])
  assert_eq(b.datatype(), a.datatype())
  for
    i, expected in [
      18446744073709551615UL, 0UL, 18446744073709551615UL, 5UL, 3UL, 5UL,
    ] {
    assert_eq(b.unsigned_at(i), expected)
  }
  assert_eq(a.take_axis(0, [1, 0]).unsigned_at(0), 3UL)
  assert_eq(a.take_axis(1, []).dataspace(), Simple([2, 0]))
  assert_eq(a.unsigned_at(0), 0UL)
  let doc = @moonh5.Document::new()
  doc.add_dataset("/gather", b)
  assert_eq(
    @moonh5.H5File::open(doc.encode()).read("/gather").bytes(),
    b.bytes(),
  )
}

///|
test "axis gather matches independent three-dimensional coordinate oracle" {
  let a = @moonh5.ArrayValue::from_signed(
    Simple([2, 3, 4]),
    Array::makei(24, i => i.to_int64()),
  )
  for axis in [0, 1, 2] {
    let last = [1, 2, 3][axis]
    let b = a.take_axis(axis, [last, 0])
    let dims = [2, 3, 4]
    dims[axis] = 2
    let mut i = 0
    for x = 0; x < dims[0]; x = x + 1 {
      for y = 0; y < dims[1]; y = y + 1 {
        for z = 0; z < dims[2]; z = z + 1 {
          let c = [x, y, z]
          c[axis] = [last, 0][c[axis]]
          assert_eq(b.signed_at(i), (c[0] * 12 + c[1] * 4 + c[2]).to_int64())
          i += 1
        }
      }
    }
  }
}

///|
test "reshape null scalar empty rules and gather validation" {
  let a = @moonh5.ArrayValue::from_signed(Simple([2]), [1L, 2L])
  assert_true(
    try {
      ignore(a.reshape(Scalar))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(a.take_axis(0, [-1]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(a.take_axis(1, []))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        a.take_axis(0, [0, 1, 0], limits={
          ..@moonh5.Limits::default(),
          max_elements: 2,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
  let n = @moonh5.ArrayValue::new(Signed(8, Little), Null, b"")
  assert_true(
    try {
      ignore(n.reshape(Simple([0])))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(n.reshape(Null).bytes(), b"")
  assert_eq(
    @moonh5.ArrayValue::from_signed(Scalar, [7L])
    .reshape(Simple([1]))
    .signed_at(0),
    7L,
  )
}

///|
test "gather a larger reversed feature axis and reshape without narrowing" {
  let source = @moonh5.ArrayValue::from_unsigned(
    Simple([32, 64]),
    Array::makei(2048, i => 18446744073709549568UL + i.to_uint64()),
  )
  let gathered = source
    .take_axis(1, Array::makei(64, i => 63 - i))
    .reshape(Simple([2048]))
  for i = 0; i < 2048; i = i + 1 {
    assert_eq(
      gathered.unsigned_at(i),
      18446744073709549568UL + (i / 64 * 64 + 63 - i % 64).to_uint64(),
    )
  }
}
