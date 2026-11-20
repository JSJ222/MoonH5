///|
pub fn ArrayValue::with_field_path(
  self : ArrayValue,
  path : Array[String],
  replacement : ArrayValue,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  let (dtype, offset) = compound_leaf(self.dtype, path)
  if dtype != replacement.dtype || self.space != replacement.space {
    raise Invalid("field replacement datatype or extent differs", 0)
  }
  let count = self.space.elements(limits~)
  if self.raw.length() > limits.max_file_bytes {
    raise Limit("field replacement bytes")
  }
  let width = dtype.width()
  let record = self.dtype.width()
  let result = self.raw.to_array()
  for row = 0; row < count; row = row + 1 {
    let target = row * record + offset
    for i = 0; i < width; i = i + 1 {
      result[target + i] = replacement.raw[row * width + i]
    }
  }
  { ..self, raw: Bytes::from_array(result), }
}
