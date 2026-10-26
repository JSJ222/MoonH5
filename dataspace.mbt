///|
pub(all) enum Dataspace {
  Scalar
  Simple(Array[Int32])
  Null
} derive(Debug, Eq)

///|
pub extend Dataspace with @debug.Debug::{to_repr}

///|
pub extend Dataspace with Eq::{equal, not_equal}

///|
/// Scalar has one element, null has none, a zero-length axis has none.
pub fn Dataspace::elements(
  self : Dataspace,
  limits~ : Limits = Limits::default(),
) -> Int32 raise H5Error {
  limits.validate()
  let n = match self {
    Scalar => 1
    Null => 0
    Simple(shape) => {
      if shape.length() == 0 || shape.length() > limits.max_rank {
        raise Limit("dataspace rank")
      }
      let mut total = 1
      for x in shape {
        if x < 0 {
          raise Invalid("negative dimension", 0)
        }
      }
      if shape.contains(0) {
        return 0
      }
      for x in shape {
        total = checked_mul(total, x)
      }
      total
    }
  }
  if n > limits.max_elements {
    raise Limit("dataspace elements")
  }
  n
}

///|
fn Dataspace::copy(self : Dataspace) -> Dataspace {
  match self {
    Simple(shape) => Simple(shape.copy())
    _ => self
  }
}

///|
fn Dataspace::encode(self : Dataspace, limits : Limits) -> Bytes raise H5Error {
  ignore(self.elements(limits~))
  let b = buffer()
  b.u8(2)
  b.u8(
    match self {
      Simple(d) => d.length()
      _ => 0
    },
  )
  b.u8(0)
  b.u8(
    match self {
      Scalar => 0
      Simple(_) => 1
      Null => 2
    },
  )
  if self is Simple(dims) {
    for dim in dims {
      b.uint(dim.to_uint64(), 8)
    }
  }
  b.finish()
}

///|
fn decode_space(
  c : Cursor,
  size_width : Int32,
  limits : Limits,
) -> Dataspace raise H5Error {
  let at = c.pos
  let version = c.u8()
  let rank = c.u8()
  let flags = c.u8()
  if rank > limits.max_rank {
    raise Limit("dataspace rank")
  }
  let kind = match version {
    1 => {
      c.skip(5)
      if rank == 0 {
        0
      } else {
        1
      }
    }
    2 => c.u8()
    _ => raise Unsupported("dataspace version", at)
  }
  if (flags & 0xfe) != 0 {
    raise Unsupported("dataspace flags", at)
  }
  let dims : Array[Int32] = []
  for i = 0; i < rank; i = i + 1 {
    dims.push(c.index(size_width))
  }
  if (flags & 1) != 0 {
    // Maximum dimensions may be unlimited; they do not change current extent.
    for i = 0; i < rank; i = i + 1 {
      ignore(c.uint(size_width))
    }
  }
  let space = match kind {
    0 if rank == 0 => Scalar
    1 if rank > 0 => Simple(dims)
    2 if rank == 0 => Null
    _ => raise Invalid("dataspace kind/rank mismatch", at)
  }
  ignore(space.elements(limits~))
  space
}

///|
test "scalar null and empty arrays are distinct" {
  let limits = Limits::default()
  for space in [Scalar, Null, Simple([2, 3]), Simple([0, 7])] {
    let bytes = space.encode(limits)
    assert_eq(decode_space(cursor(bytes, 0, bytes.length()), 8, limits), space)
  }
  assert_eq(Scalar.elements(), 1)
  assert_eq(Null.elements(), 0)
  assert_eq(Simple([10, 0]).elements(), 0)
  assert_true(
    try {
      ignore(Simple([2147483647, 2]).elements())
      false
    } catch {
      _ => true
    },
  )
}
