///|
test "all standard integer widths preserve signed and unsigned extremes" {
  for width in [1, 2, 4, 8] {
    for order in [Little, Big] {
      let sign = 1UL << (width * 8 - 1)
      let raw = buffer()
      raw.uint(sign, width)
      let little = ArrayValue::new(Signed(width, Little), Scalar, raw.finish())
      let value = little.with_byte_order(order)
      let expected = if width == 8 {
        -9223372036854775808L
      } else {
        -sign.reinterpret_as_int64()
      }
      assert_eq(value.signed_at(0), expected)
      let unsigned = ArrayValue::new(
        Unsigned(width, order),
        Scalar,
        value.bytes(),
      )
      assert_eq(unsigned.unsigned_at(0), sign)
      let doc = Document::new()
      doc.add_dataset("/value", value)
      let decoded = H5File::open(doc.encode()).read("/value")
      assert_eq(decoded.signed_at(0), expected)
      assert_eq(decoded.datatype(), Signed(width, order))
    }
  }
}

///|
test "small shape hyperslabs agree with independent coordinate enumeration" {
  for rows = 1; rows <= 5; rows = rows + 1 {
    for cols = 1; cols <= 6; cols = cols + 1 {
      let raw = ArrayValue::from_signed(
        Simple([rows, cols]),
        Array::makei(rows * cols, i => i.to_int64()),
      )
      for row_start = 0; row_start < rows; row_start = row_start + 1 {
        for col_start = 0; col_start < cols; col_start = col_start + 1 {
          for step in [1, 2, 3] {
            let nr = (rows - row_start + step - 1) / step
            let nc = (cols - col_start + step - 1) / step
            let s = Selection::new(raw.space, [
              { start: row_start, stride: step, count: nr, block: 1, },
              { start: col_start, stride: step, count: nc, block: 1, },
            ])
            let selected = raw.select(s)
            let mut at = 0
            for r = row_start; r < rows; r = r + step {
              for c = col_start; c < cols; c = c + step {
                assert_eq(selected.signed_at(at), (r * cols + c).to_int64())
                at += 1
              }
            }
            assert_eq(at, nr * nc)
            let result = raw.with_selection(s, selected)
            assert_eq(result.bytes(), raw.bytes())
          }
        }
      }
    }
  }
}

///|
test "serialization is independent of document insertion and attribute order" {
  let a = Document::new()
  let b = Document::new()
  for name in ["z", "a", "m"] {
    a.add_dataset("/" + name, ArrayValue::from_signed(Scalar, [5L]))
  }
  for name in ["m", "a", "z"] {
    b.add_dataset("/" + name, ArrayValue::from_signed(Scalar, [5L]))
  }
  for name in ["units", "version"] {
    a.set_attribute("/a", name, ArrayValue::from_signed(Scalar, [1L]))
  }
  for name in ["version", "units"] {
    b.set_attribute("/a", name, ArrayValue::from_signed(Scalar, [1L]))
  }
  assert_eq(a.encode(), b.encode())
}

///|
test "numeric float32 byte order is interpreted without float64 wire conversion" {
  let v = ArrayValue::new(
    Float(4, Big),
    Simple([3]),
    b"\x3f\x80\x00\x00\xc0\x20\x00\x00\x80\x00\x00\x00",
  )
  assert_eq(v.float_at(0), 1.0)
  assert_eq(v.float_at(1), -2.5)
  assert_eq(v.float_at(2).reinterpret_as_uint64(), 0x8000000000000000UL)
}

///|
test "fixed-string padding modes do not strip significant interior bytes" {
  let cases = [
    (NullTerminated, b"a\x00bc", "a"),
    (NullPadded, b"a\x00b\x00", "a\u0000b"),
    (SpacePadded, b"a b ", "a b"),
  ]
  for (padding, bytes, expected) in cases {
    let v = ArrayValue::new(FixedString(4, padding, false), Scalar, bytes)
    assert_eq(v.string_at(0), expected)
  }
  let malformed = ArrayValue::new(
    FixedString(2, NullPadded, true),
    Scalar,
    b"\xc3\x28",
  )
  assert_true(
    try {
      ignore(malformed.string_at(0))
      false
    } catch {
      _ => true
    },
  )
}
