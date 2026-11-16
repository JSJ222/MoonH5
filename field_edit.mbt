///|
/// Replace one compound field without changing the datatype, other fields or
/// record padding. The replacement must match the original field and extent.
pub fn ArrayValue::with_field(
  self : ArrayValue,
  name : String,
  replacement : ArrayValue,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  guard self.dtype is Compound(width, members) else {
    raise Invalid("compound field replacement", 0)
  }
  guard members.iter().find_first(m => m.name == name) is Some(field) else {
    raise NotFound(name)
  }
  if field.datatype != replacement.dtype || self.space != replacement.space {
    raise Invalid("field replacement datatype or extent differs", 0)
  }
  ignore(self.space.elements(limits~))
  if self.raw.length() > limits.max_file_bytes {
    raise Limit("field replacement bytes")
  }
  if self.raw.is_empty() {
    return self
  }
  let field_width = field.datatype.width()
  let out = self.raw.to_array()
  let count = self.raw.length() / width
  for row = 0; row < count; row = row + 1 {
    let target = row * width + field.offset
    let source = row * field_width
    for i = 0; i < field_width; i = i + 1 {
      out[target + i] = replacement.raw[source + i]
    }
  }
  { ..self, raw: Bytes::from_array(out), }
}

///|
test "compound field replacement preserves neighboring fields and padding" {
  let dtype : DataType = Compound(4, [
    { name: "id", offset: 0, datatype: Unsigned(1, Little), },
    { name: "reading", offset: 2, datatype: Unsigned(2, Big), },
  ])
  let source = ArrayValue::new(
    dtype,
    Simple([2]),
    b"\x01\xff\x00\x20\x02\xee\x00\x21",
  )
  let readings = ArrayValue::new(
    Unsigned(2, Big),
    Simple([2]),
    b"\x01\x23\x04\x56",
  )
  let patched = source.with_field("reading", readings)
  assert_eq(patched.bytes(), b"\x01\xff\x01\x23\x02\xee\x04\x56")
  assert_eq(source.field("reading").unsigned_at(0), 32UL)
  assert_true(
    try {
      ignore(source.with_field("reading", readings.with_byte_order(Little)))
      false
    } catch {
      _ => true
    },
  )
}
