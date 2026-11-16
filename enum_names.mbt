///|
/// Decode an enum array in dataset order. Unmapped values yield None.
/// For aliased values, choose the first declaration as enum_name_at does.
pub fn ArrayValue::enum_names(
  self : ArrayValue,
  limits~ : Limits = Limits::default(),
) -> Array[String?] raise H5Error {
  guard self.dtype is EnumType(base, entries) else {
    raise Invalid("not enum datatype", 0)
  }
  let count = self.space.elements(limits~)
  let width = base.width()
  let names : Map[Bytes, String] = Map([])
  for (name, value) in entries {
    if !names.contains(value) {
      names[value] = name
    }
  }
  Array::makei(count, i => names.get(bytes_at(self.raw, i * width, width)))
}

///|
test "bulk enum decoding preserves ordering and unknown codes" {
  let dtype : DataType = EnumType(Unsigned(2, Big), [
    ("low", b"\x00\x01"),
    ("high", b"\x00\x02"),
  ])
  let values = ArrayValue::new(dtype, Simple([3]), b"\x00\x02\x00\xff\x00\x01")
  assert_eq(values.enum_names(), [Some("high"), None, Some("low")])
  assert_eq(ArrayValue::new(dtype, Null, b"").enum_names(), [])
}
