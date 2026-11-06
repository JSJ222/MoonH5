///|
/// Reshape without reordering or converting samples. Null retains null identity.
pub fn ArrayValue::reshape(
  self : ArrayValue,
  space : Dataspace,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  let source_null = self.space is Null
  let target_null = space is Null
  if source_null != target_null ||
    self.space.elements(limits~) != space.elements(limits~) {
    raise Invalid("reshape element count or null dataspace", 0)
  }
  ArrayValue::new(self.dtype, space, self.raw, limits~)
}

///|
/// Gather an axis in caller order; duplicates duplicate samples, preserving bits.
pub fn ArrayValue::take_axis(
  self : ArrayValue,
  axis : Int32,
  indices : Array[Int32],
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  let shape = match self.space {
    Simple(s) => s
    _ => raise Invalid("gather simple dataspace", 0)
  }
  ignore(self.space.elements(limits~))
  if axis < 0 || axis >= shape.length() {
    raise Invalid("gather axis", axis)
  }
  for index in indices {
    if index < 0 || index >= shape[axis] {
      raise Invalid("gather index", index)
    }
  }
  let next = shape.copy()
  next[axis] = indices.length()
  let count = Simple(next).elements(limits~)
  let width = self.dtype.width()
  let size = checked_mul(count, width)
  if size > limits.max_file_bytes {
    raise Limit("gather bytes")
  }
  let output = Array::make(size, b'\x00')
  if count > 0 {
    let mut inner = width
    for i = axis + 1; i < shape.length(); i = i + 1 {
      inner = checked_mul(inner, shape[i])
    }
    let source_block = checked_mul(inner, shape[axis])
    let target_block = checked_mul(inner, indices.length())
    let mut outer = 1
    for i = 0; i < axis; i = i + 1 {
      outer = checked_mul(outer, shape[i])
    }
    for n = 0; n < outer; n = n + 1 {
      for k, index in indices {
        for b = 0; b < inner; b = b + 1 {
          output[n * target_block + k * inner + b] = self.raw[n * source_block +
            index * inner +
            b]
        }
      }
    }
  }
  ArrayValue::new(self.dtype, Simple(next), Bytes::from_array(output), limits~)
}
