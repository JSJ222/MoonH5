///|
/// Returns new storage, preserving the source even if validation fails.
pub fn ArrayValue::with_selection(
  self : ArrayValue,
  selection : Selection,
  replacement : ArrayValue,
) -> ArrayValue raise H5Error {
  if self.space != selection.source || replacement.space != selection.result {
    raise Invalid("replacement/selection extent mismatch", 0)
  }
  if self.dtype != replacement.dtype {
    raise Invalid("replacement datatype differs", 0)
  }
  if self.raw.length() > selection.limits.max_file_bytes {
    raise Limit("patched array bytes")
  }
  let spans = selection.spans(self.dtype)
  let out = self.raw.to_array()
  for span in spans {
    for i = 0; i < span.length; i = i + 1 {
      out[span.source_byte + i] = replacement.raw[span.output_byte + i]
    }
  }
  ArrayValue::new(
    self.dtype,
    self.space,
    Bytes::from_array(out),
    limits=selection.limits,
  )
}

///|
/// Exchange byte order only; floating payloads and integer bit patterns survive.
pub fn ArrayValue::with_byte_order(
  self : ArrayValue,
  order : ByteOrder,
) -> ArrayValue raise H5Error {
  let (dtype, old) = match self.dtype {
    Signed(width, old) => (Signed(width, order), old)
    Unsigned(width, old) => (Unsigned(width, order), old)
    Float(width, old) => (Float(width, order), old)
    FixedString(_, _, _) => return self
    Compound(_, _) | ArrayType(_, _) | EnumType(_, _) =>
      raise Unsupported(
        "use field/base projection for structured byte-order conversion", 0,
      )
  }
  if old == order {
    return self
  }
  let width = dtype.width()
  let out = self.raw.to_array()
  for at = 0; at < out.length(); at = at + width {
    for j = 0; j < width; j = j + 1 {
      out[at + j] = self.raw[at + width - 1 - j]
    }
  }
  // The source has already been validated; no new extent is introduced.
  { ..self, dtype, raw: Bytes::from_array(out), }
}

///|
test "functional hyperslab update is atomic and preserves unselected cells" {
  let a = ArrayValue::from_signed(
    Simple([3, 4]),
    Array::makei(12, i => i.to_int64()),
  )
  let s = Selection::new(a.space, [
    { start: 0, stride: 2, count: 2, block: 1, },
    { start: 1, stride: 1, count: 2, block: 1, },
  ])
  let replacement = ArrayValue::from_signed(Simple([2, 2]), [40L, 41L, 42L, 43L])
  let updated = a.with_selection(s, replacement)
  assert_eq(a.signed_at(1), 1L)
  assert_eq(updated.signed_at(1), 40L)
  assert_eq(updated.signed_at(2), 41L)
  assert_eq(updated.signed_at(9), 42L)
  assert_eq(updated.signed_at(0), 0L)
  assert_eq(updated.select(s).bytes(), replacement.bytes())
  assert_true(
    try {
      ignore(a.with_selection(s, ArrayValue::from_signed(Scalar, [1L])))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "byte order change preserves negative zero NaN and large integers" {
  let bits = ArrayValue::new(
    Float(8, Little),
    Simple([2]),
    b"\x00\x00\x00\x00\x00\x00\x00\x80\x01\x00\x00\x00\x00\x00\xf8\x7f",
  )
  let big = bits.with_byte_order(Big)
  assert_eq(big.float_at(0).reinterpret_as_uint64(), 0x8000000000000000UL)
  assert_eq(big.float_at(1).reinterpret_as_uint64(), 0x7ff8000000000001UL)
  assert_eq(big.with_byte_order(Little).bytes(), bits.bytes())
  let integer = ArrayValue::from_unsigned(Scalar, [0xfedcba9876543210UL])
  assert_eq(integer.with_byte_order(Big).unsigned_at(0), 0xfedcba9876543210UL)
}
