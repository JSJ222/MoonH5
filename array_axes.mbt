///|
/// Reorder axes in row-major storage without converting sample bits.
pub fn ArrayValue::transpose(
  self : ArrayValue,
  axes : Array[Int32],
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  let shape = match self.space {
    Simple(s) => s
    _ => raise Invalid("transpose requires simple dataspace", 0)
  }
  ignore(self.space.elements(limits~))
  if axes.length() != shape.length() {
    raise Invalid("axis permutation rank", 0)
  }
  let seen = Array::make(shape.length(), false)
  for axis in axes {
    if axis < 0 || axis >= shape.length() || seen[axis] {
      raise Invalid("invalid or repeated axis", axis)
    }
    seen[axis] = true
  }
  let next_shape = axes.map(a => shape[a])
  let count = self.length()
  let width = self.dtype.width()
  let output_bytes = checked_mul(count, width)
  if output_bytes > limits.max_file_bytes {
    raise Limit("transpose bytes")
  }
  let output = Array::make(output_bytes, b'\x00')
  // Empty dimensions need no stride products, which could otherwise overflow.
  if count > 0 {
    let strides = Array::make(shape.length(), 1)
    for i = shape.length() - 2; i >= 0; i = i - 1 {
      strides[i] = checked_mul(strides[i + 1], shape[i + 1])
    }
    for n = 0; n < count; n = n + 1 {
      let mut remainder = n
      let mut source = 0
      for i = axes.length() - 1; i >= 0; i = i - 1 {
        let coordinate = remainder % next_shape[i]
        remainder = remainder / next_shape[i]
        source += coordinate * strides[axes[i]]
      }
      for b = 0; b < width; b = b + 1 {
        output[n * width + b] = self.raw[source * width + b]
      }
    }
  }
  ArrayValue::new(
    self.dtype,
    Simple(next_shape),
    Bytes::from_array(output),
    limits~,
  )
}

///|
/// Concatenate compatible fixed-width arrays on one axis. No implicit casts.
pub fn ArrayValue::concat_axis(
  self : ArrayValue,
  other : ArrayValue,
  axis : Int32,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  let left = match self.space {
    Simple(s) => s
    _ => raise Invalid("concat simple dataspace", 0)
  }
  let right = match other.space {
    Simple(s) => s
    _ => raise Invalid("concat simple dataspace", 0)
  }
  ignore(self.space.elements(limits~))
  ignore(other.space.elements(limits~))
  if self.dtype != other.dtype ||
    left.length() != right.length() ||
    axis < 0 ||
    axis >= left.length() {
    raise Invalid("concat type, rank or axis mismatch", axis)
  }
  for i = 0; i < left.length(); i = i + 1 {
    if i != axis && left[i] != right[i] {
      raise Invalid("concat non-axis extent", i)
    }
  }
  if left[axis] > 2147483647 - right[axis] {
    raise Limit("concat extent")
  }
  let shape = left.copy()
  shape[axis] += right[axis]
  let count = Simple(shape).elements(limits~)
  let width = self.dtype.width()
  let size = checked_mul(count, width)
  if size > limits.max_file_bytes {
    raise Limit("concat bytes")
  }
  let bytes = Array::make(size, b'\x00')
  if count > 0 {
    let mut inner = width
    for i = axis + 1; i < left.length(); i = i + 1 {
      inner = checked_mul(inner, left[i])
    }
    let lblock = checked_mul(inner, left[axis])
    let rblock = checked_mul(inner, right[axis])
    let mut outer = 1
    for i = 0; i < axis; i = i + 1 {
      outer = checked_mul(outer, left[i])
    }
    for n = 0; n < outer; n = n + 1 {
      let dest = n * (lblock + rblock)
      for i = 0; i < lblock; i = i + 1 {
        bytes[dest + i] = self.raw[n * lblock + i]
      }
      for i = 0; i < rblock; i = i + 1 {
        bytes[dest + lblock + i] = other.raw[n * rblock + i]
      }
    }
  }
  ArrayValue::new(self.dtype, Simple(shape), Bytes::from_array(bytes), limits~)
}
