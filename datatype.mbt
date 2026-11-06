///|
pub(all) enum ByteOrder {
  Little
  Big
} derive(Debug, Eq)

///|
pub extend ByteOrder with @debug.Debug::{to_repr}

///|
pub extend ByteOrder with Eq::{equal, not_equal}

///|
pub(all) enum StringPadding {
  NullTerminated
  NullPadded
  SpacePadded
} derive(Debug, Eq)

///|
pub extend StringPadding with @debug.Debug::{to_repr}

///|
pub extend StringPadding with Eq::{equal, not_equal}

///|
/// Fixed-width atomic and recursively structured HDF5 element types.
pub(all) enum DataType {
  Signed(Int32, ByteOrder)
  Unsigned(Int32, ByteOrder)
  Float(Int32, ByteOrder)
  FixedString(Int32, StringPadding, Bool)
  Compound(Int32, Array[CompoundMember])
  ArrayType(Array[Int32], DataType)
  EnumType(DataType, Array[(String, Bytes)])
} derive(Debug, Eq)

///|
pub extend DataType with @debug.Debug::{to_repr}

///|
pub extend DataType with Eq::{equal, not_equal}

///|
pub fn DataType::width(self : DataType) -> Int32 raise H5Error {
  type_width(self, 0, Ref(4096))
}

///|
fn DataType::encode(self : DataType) -> Bytes raise H5Error {
  let n = self.width()
  let b = buffer()
  match self {
    Signed(_, order) | Unsigned(_, order) => {
      b.u8(0x10)
      let sign = match self {
        Signed(_, _) => 8
        _ => 0
      }
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
    Compound(_, members) => {
      b.u8(0x36)
      b.uint(members.length().to_uint64(), 3)
      b.uint(n.to_uint64(), 4)
      for field in members {
        b.bytes(@utf8.encode(field.name))
        b.u8(0)
        b.uint(field.offset.to_uint64(), type_offset_width(n))
        b.bytes(field.datatype.encode())
      }
    }
    ArrayType(shape, base) => {
      b.u8(0x3a)
      b.uint(0UL, 3)
      b.uint(n.to_uint64(), 4)
      b.u8(shape.length())
      for dim in shape {
        b.uint(dim.to_uint64(), 4)
      }
      b.bytes(base.encode())
    }
    EnumType(base, entries) => {
      b.u8(0x38)
      b.uint(entries.length().to_uint64(), 3)
      b.uint(n.to_uint64(), 4)
      b.bytes(base.encode())
      for (name, _) in entries {
        b.bytes(@utf8.encode(name))
        b.u8(0)
      }
      for (_, value) in entries {
        b.bytes(value)
      }
    }
    FixedString(_, padding, utf8) => {
      b.u8(0x13)
      let pad = match padding {
        NullTerminated => 0
        NullPadded => 1
        SpacePadded => 2
      }
      b.u8(pad | (if utf8 { 16 } else { 0 }))
      b.uint(0UL, 2)
      b.uint(n.to_uint64(), 4)
    }
  }
  b.finish()
}

///|
fn decode_type(c : Cursor) -> DataType raise H5Error {
  decode_type_inner(c, 0, Ref(4096))
}

///|
fn decode_type_inner(
  c : Cursor,
  depth : Int32,
  budget : Ref[Int32],
) -> DataType raise H5Error {
  budget.val -= 1
  if depth > 32 || budget.val < 0 {
    raise Limit("datatype recursion/nodes")
  }
  let start = c.pos
  let tag = c.u8()
  if tag >> 4 < 1 || tag >> 4 > 4 {
    raise Unsupported("datatype version", start)
  }
  let flags = c.index(2)
  let flag2 = c.u8()
  let n = c.index(4)
  let order = if (flags & 1) == 1 { Big } else { Little }
  let dtype = match tag & 15 {
    0 => {
      if (flags & 0xfff6) != 0 ||
        flag2 != 0 ||
        c.index(2) != 0 ||
        c.index(2) != checked_mul(n, 8) {
        raise Unsupported("noncanonical integer datatype", start)
      }
      if (flags & 8) != 0 {
        Signed(n, order)
      } else {
        Unsigned(n, order)
      }
    }
    1 => {
      let tail = c.bytes(12)
      let candidate = Float(n, order)
      let expected = candidate.encode()
      if flags !=
        (
          0x20 |
          (if order == Big { 1 } else { 0 }) |
          ((if n == 4 { 31 } else { 63 }) << 8)
        ) ||
        flag2 != 0 ||
        tail != expected[8:].to_owned() {
        raise Unsupported("non-IEEE floating datatype", start)
      }
      candidate
    }
    3 => {
      if flag2 != 0 || flags > 0x12 || (flags & 15) > 2 {
        raise Unsupported("string charset or padding", start)
      }
      FixedString(
        n,
        match flags & 15 {
          0 => NullTerminated
          1 => NullPadded
          _ => SpacePadded
        },
        (flags & 16) != 0,
      )
    }
    6 => {
      if flag2 != 0 || flags < 1 || flags > 256 {
        raise Limit("compound field count")
      }
      let members : Array[CompoundMember] = []
      for i = 0; i < flags; i = i + 1 {
        let name = type_member_name(c, tag >> 4 < 3)
        let offset = c.index(
          if tag >> 4 < 3 {
            4
          } else {
            type_offset_width(n)
          },
        )
        if tag >> 4 == 1 {
          let rank = c.u8()
          c.skip(3)
          if rank != 0 {
            raise Unsupported("legacy inline compound arrays", start)
          }
          c.skip(24)
        }
        members.push({
          name,
          offset,
          datatype: decode_type_inner(c, depth + 1, budget),
        })
      }
      Compound(n, members)
    }
    10 => {
      if flags != 0 || flag2 != 0 || tag >> 4 < 2 {
        raise Unsupported("array datatype flags/version", start)
      }
      let rank = c.u8()
      if rank < 1 || rank > 32 {
        raise Limit("array datatype rank")
      }
      if tag >> 4 == 2 {
        c.skip(3)
      }
      let shape = Array::makei(rank, _ => c.index(4))
      if tag >> 4 == 2 {
        for i = 0; i < rank; i = i + 1 {
          if c.index(4) != i {
            raise Unsupported("array datatype permutation", start)
          }
        }
      }
      let base = decode_type_inner(c, depth + 1, budget)
      let dtype = ArrayType(shape, base)
      if dtype.width() != n {
        raise Invalid("array datatype size", start)
      }
      dtype
    }
    8 => {
      if flag2 != 0 || flags < 1 || flags > 256 {
        raise Limit("enum field count")
      }
      let base = decode_type_inner(c, depth + 1, budget)
      if base.width() != n {
        raise Invalid("enum base size", start)
      }
      let names = Array::makei(flags, _ => type_member_name(c, tag >> 4 < 3))
      EnumType(base, names.map(name => (name, c.bytes(n))))
    }
    _ => raise Unsupported("vlen/reference/unknown datatype", start)
  }
  ignore(dtype.width())
  dtype
}

///|
test "atomic datatypes roundtrip without losing endian or padding" {
  let cases = [
    Signed(8, Little),
    Unsigned(2, Big),
    Float(4, Little),
    Float(8, Big),
    FixedString(17, SpacePadded, true),
  ]
  for dtype in cases {
    let bytes = dtype.encode()
    assert_eq(decode_type(cursor(bytes, 0, bytes.length())), dtype)
  }
  assert_true(
    try {
      ignore(Signed(3, Little).width())
      false
    } catch {
      _ => true
    },
  )
}
