///|
fn compound_leaf(
  dtype : DataType,
  path : Array[String],
) -> (DataType, Int32) raise H5Error {
  if path.is_empty() || path.length() > 32 {
    raise Invalid("compound field path length", 0)
  }
  let mut leaf = dtype
  let mut offset = 0
  for name in path {
    guard leaf is Compound(_, members) else {
      raise Invalid("field path crosses a non-compound type", 0)
    }
    guard members.iter().find_first(field => field.name == name) is Some(field) else {
      raise NotFound(name)
    }
    offset = checked_add(offset, field.offset)
    leaf = field.datatype
  }
  (leaf, offset)
}

///|
pub fn ArrayValue::field_path(
  self : ArrayValue,
  path : Array[String],
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  let (dtype, offset) = compound_leaf(self.dtype, path)
  let count = self.space.elements(limits~)
  let width = dtype.width()
  if checked_mul(count, width) > limits.max_file_bytes {
    raise Limit("field projection bytes")
  }
  let record = self.dtype.width()
  let b = buffer()
  for i = 0; i < count; i = i + 1 {
    b.bytes(bytes_at(self.raw, i * record + offset, width))
  }
  ArrayValue::new(dtype, self.space, b.finish(), limits~)
}
