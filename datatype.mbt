///|
pub(all) enum ByteOrder { Little; Big } derive(Debug, Eq)
///|
pub extend ByteOrder with @debug.Debug::{to_repr}
///|
pub extend ByteOrder with Eq::{equal, not_equal}

///|
pub(all) enum StringPadding { NullTerminated; NullPadded; SpacePadded } derive(Debug, Eq)
///|
pub extend StringPadding with @debug.Debug::{to_repr}
///|
pub extend StringPadding with Eq::{equal, not_equal}

///| Only fixed-size atomic types belong to the initial profile.
pub(all) enum DataType {
  Signed(Int, ByteOrder)
  Unsigned(Int, ByteOrder)
  Float(Int, ByteOrder)
  FixedString(Int, StringPadding, Bool)
} derive(Debug, Eq)
///|
pub extend DataType with @debug.Debug::{to_repr}
///|
pub extend DataType with Eq::{equal, not_equal}

///|
pub fn DataType::width(self : DataType) -> Int raise H5Error {
  match self {
    Signed(n, _) | Unsigned(n, _) if n == 1 || n == 2 || n == 4 || n == 8 => n
    Float(n, _) if n == 4 || n == 8 => n
    FixedString(n, _, _) if n > 0 && n <= 65535 => n
    _ => raise Unsupported("unsupported atomic width", 0)
  }
}

///|
fn DataType::encode(self : DataType) -> Bytes raise H5Error {
  let n = self.width()
  let b = buffer()
  match self {
    Signed(_, order) | Unsigned(_, order) => {
      b.u8(0x10)
      let sign = match self { Signed(_, _) => 8; _ => 0 }
      b.u8(sign | (if order == Big { 1 } else { 0 }))
      b.uint(0UL, 2)
      b.uint(n.to_uint64(), 4)
      b.uint(0UL, 2)
      b.uint((n * 8).to_uint64(), 2)
    }
    Float(_, order) => {
      b.u8(0x11)
      b.u8(0x20 | (if order == Big { 1 } else { 0 }))
      b.u8(if n == 4 { 31 } else { 63 })
      b.u8(0)
      b.uint(n.to_uint64(), 4)
      b.uint(0UL, 2)
      b.uint((n * 8).to_uint64(), 2)
      b.u8(if n == 4 { 23 } else { 52 })
      b.u8(if n == 4 { 8 } else { 11 })
      b.u8(0)
      b.u8(if n == 4 { 23 } else { 52 })
      b.uint(if n == 4 { 127UL } else { 1023UL }, 4)
    }
    FixedString(_, padding, utf8) => {
      b.u8(0x13)
      let pad = match padding { NullTerminated => 0; NullPadded => 1; SpacePadded => 2 }
      b.u8(pad | (if utf8 { 16 } else { 0 }))
      b.uint(0UL, 2)
      b.uint(n.to_uint64(), 4)
    }
  }
  b.finish()
}

///|
fn decode_type(c : Cursor) -> DataType raise H5Error {
  let start = c.pos
  let tag = c.u8()
  if tag >> 4 < 1 || tag >> 4 > 4 { raise Unsupported("datatype version", start) }
  let flags = c.index(2)
  let flag2 = c.u8()
  let n = c.index(4)
  let order = if (flags & 1) == 1 { Big } else { Little }
  let dtype = match tag & 15 {
    0 => {
      if (flags & 0xfff6) != 0 || flag2 != 0 || c.index(2) != 0 || c.index(2) != checked_mul(n, 8) {
        raise Unsupported("noncanonical integer datatype", start)
      }
      if (flags & 8) != 0 { Signed(n, order) } else { Unsigned(n, order) }
    }
    1 => {
      let tail = c.bytes(12)
      let candidate = Float(n, order)
      let expected = candidate.encode()
      if flags != (0x20 | (if order == Big { 1 } else { 0 }) | ((if n == 4 { 31 } else { 63 }) << 8)) ||
        flag2 != 0 || tail != expected[8:].to_owned() {
        raise Unsupported("non-IEEE floating datatype", start)
      }
      candidate
    }
    3 => {
      if flag2 != 0 || flags > 0x12 || (flags & 15) > 2 {
        raise Unsupported("string charset or padding", start)
      }
      FixedString(n, match flags & 15 { 0 => NullTerminated; 1 => NullPadded; _ => SpacePadded }, (flags & 16) != 0)
    }
    _ => raise Unsupported("compound/vlen/reference datatype", start)
  }
  ignore(dtype.width())
  dtype
}

///|
test "atomic datatypes roundtrip without losing endian or padding" {
  let cases = [Signed(8, Little), Unsigned(2, Big), Float(4, Little), Float(8, Big), FixedString(17, SpacePadded, true)]
  for dtype in cases {
    let bytes = dtype.encode()
    assert_eq(decode_type(cursor(bytes, 0, bytes.length())), dtype)
  }
  assert_true(try { ignore(Signed(3, Little).width()); false } catch { _ => true })
}
