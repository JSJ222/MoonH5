///|
/// Immutable byte storage; shape accessors return defensive copies.
pub struct ArrayValue {
  dtype : DataType
  space : Dataspace
  raw : Bytes
} derive(Debug)

///|
pub extend ArrayValue with @debug.Debug::{to_repr}

///|
/// Data bytes use the datatype's declared byte order, not host endianness.
pub fn ArrayValue::new(
  dtype : DataType,
  space : Dataspace,
  raw : Bytes,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  let size = checked_mul(space.elements(limits~), dtype.width())
  if size > limits.max_file_bytes {
    raise Limit("array byte size")
  }
  if raw.length() != size {
    raise Invalid("array byte length differs from extent", 0)
  }
  { dtype, space: space.copy(), raw, }
}

///|
pub fn ArrayValue::datatype(self : ArrayValue) -> DataType {
  self.dtype
}

///|
pub fn ArrayValue::dataspace(self : ArrayValue) -> Dataspace {
  self.space.copy()
}

///|
pub fn ArrayValue::bytes(self : ArrayValue) -> Bytes {
  self.raw
}

///|
pub fn ArrayValue::length(self : ArrayValue) -> Int32 raise H5Error {
  self.raw.length() / self.dtype.width()
}

///|
fn value_bits(
  data : Bytes,
  start : Int32,
  width : Int32,
  order : ByteOrder,
) -> UInt64 raise H5Error {
  let bytes = bytes_at(data, start, width)
  let mut bits = 0UL
  for i = 0; i < width; i = i + 1 {
    let at = if order == Little { i } else { width - 1 - i }
    bits = bits | (bytes[at].to_uint64() << (8 * i))
  }
  bits
}

///|
fn ArrayValue::offset(self : ArrayValue, index : Int32) -> Int32 raise H5Error {
  if index < 0 || index >= self.length() {
    raise Invalid("array index outside extent", index)
  }
  checked_mul(index, self.dtype.width())
}

///|
/// No conversion through Double; 64-bit integers retain every bit.
pub fn ArrayValue::signed_at(
  self : ArrayValue,
  index : Int32,
) -> Int64 raise H5Error {
  let offset = self.offset(index)
  guard self.dtype is Signed(width, order) else {
    raise Invalid("not signed integer data", index)
  }
  let bits = value_bits(self.raw, offset, width, order)
  let signed = bits.reinterpret_as_int64()
  if width == 8 {
    signed
  } else {
    signed << (64 - width * 8) >> (64 - width * 8)
  }
}

///|
pub fn ArrayValue::unsigned_at(
  self : ArrayValue,
  index : Int32,
) -> UInt64 raise H5Error {
  let offset = self.offset(index)
  guard self.dtype is Unsigned(width, order) else {
    raise Invalid("not unsigned integer data", index)
  }
  value_bits(self.raw, offset, width, order)
}

///|
pub fn ArrayValue::float_at(
  self : ArrayValue,
  index : Int32,
) -> Double raise H5Error {
  let offset = self.offset(index)
  guard self.dtype is Float(width, order) else {
    raise Invalid("not floating data", index)
  }
  let bits = value_bits(self.raw, offset, width, order)
  if width == 8 {
    bits.reinterpret_as_double()
  } else {
    Float::reinterpret_from_uint(bits.to_uint()).to_double()
  }
}

///|
pub fn ArrayValue::string_at(
  self : ArrayValue,
  index : Int32,
) -> String raise H5Error {
  let offset = self.offset(index)
  guard self.dtype is FixedString(width, padding, unicode) else {
    raise Invalid("not fixed string data", index)
  }
  let bytes = bytes_at(self.raw, offset, width)
  let mut end = width
  match padding {
    NullTerminated =>
      for i = 0; i < width; i = i + 1 {
        if bytes[i] == 0 {
          end = i
          break
        }
      }
    NullPadded =>
      while end > 0 && bytes[end - 1] == 0 {
        end -= 1
      }
    SpacePadded =>
      while end > 0 && bytes[end - 1] == 32 {
        end -= 1
      }
  }
  let trimmed = bytes[:end].to_owned()
  if !unicode {
    for x in trimmed {
      if x > 127 {
        raise Invalid("non-ASCII fixed string", offset)
      }
    }
  }
  @utf8.decode(trimmed) catch {
    _ => raise Invalid("invalid UTF-8 string", offset)
  }
}

///|
pub fn ArrayValue::from_signed(
  space : Dataspace,
  values : Array[Int64],
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  if values.length() != space.elements(limits~) {
    raise Invalid("integer count differs from extent", 0)
  }
  if checked_mul(values.length(), 8) > limits.max_file_bytes {
    raise Limit("array bytes")
  }
  let b = buffer()
  for v in values {
    b.uint(v.reinterpret_as_uint64(), 8)
  }
  ArrayValue::new(Signed(8, Little), space, b.finish(), limits~)
}

///|
pub fn ArrayValue::from_unsigned(
  space : Dataspace,
  values : Array[UInt64],
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  if values.length() != space.elements(limits~) {
    raise Invalid("unsigned count differs from extent", 0)
  }
  if checked_mul(values.length(), 8) > limits.max_file_bytes {
    raise Limit("array bytes")
  }
  let b = buffer()
  for v in values {
    b.uint(v, 8)
  }
  ArrayValue::new(Unsigned(8, Little), space, b.finish(), limits~)
}

///|
pub fn ArrayValue::from_floats(
  space : Dataspace,
  values : Array[Double],
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  if values.length() != space.elements(limits~) {
    raise Invalid("float count differs from extent", 0)
  }
  if checked_mul(values.length(), 8) > limits.max_file_bytes {
    raise Limit("array bytes")
  }
  let b = buffer()
  for v in values {
    b.uint(v.reinterpret_as_uint64(), 8)
  }
  ArrayValue::new(Float(8, Little), space, b.finish(), limits~)
}

///|
pub fn ArrayValue::from_strings(
  space : Dataspace,
  values : Array[String],
  width : Int32,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  let dtype = FixedString(width, NullPadded, true)
  ignore(dtype.width())
  if values.length() != space.elements(limits~) {
    raise Invalid("string count differs from extent", 0)
  }
  if checked_mul(values.length(), width) > limits.max_file_bytes {
    raise Limit("array bytes")
  }
  let b = buffer()
  for v in values {
    let bytes = @utf8.encode(v)
    if bytes.length() > width {
      raise Invalid("string does not fit fixed width", 0)
    }
    b.bytes(bytes)
    b.zeros(width - bytes.length())
  }
  ArrayValue::new(dtype, space, b.finish(), limits~)
}

///|
test "typed arrays preserve int64 extremes and floating payloads" {
  let v = ArrayValue::from_signed(Simple([3]), [
    -9223372036854775808L, 0L, 9223372036854775807L,
  ])
  assert_eq(v.signed_at(0), -9223372036854775808L)
  assert_eq(v.signed_at(2), 9223372036854775807L)
  let u = ArrayValue::from_unsigned(Scalar, [0xffffffffffffffffUL])
  assert_eq(u.unsigned_at(0), 0xffffffffffffffffUL)
  let f = ArrayValue::from_floats(Simple([2]), [-0.0, 1.25])
  assert_eq(f.float_at(0).reinterpret_as_uint64(), 0x8000000000000000UL)
  assert_eq(f.float_at(1), 1.25)
  assert_true(
    try {
      ignore(v.signed_at(3))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(v.unsigned_at(0))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "fixed strings support UTF8 and reject byte truncation" {
  let v = ArrayValue::from_strings(Simple([2]), ["温度", ""], 6)
  assert_eq(v.string_at(0), "温度")
  assert_eq(v.string_at(1), "")
  assert_true(
    try {
      ignore(ArrayValue::from_strings(Scalar, ["温度"], 5))
      false
    } catch {
      _ => true
    },
  )
  let shape = [2]
  let a = ArrayValue::from_signed(Simple(shape), [1L, 2L])
  shape[0] = 99
  assert_eq(a.length(), 2)
}
