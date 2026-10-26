///|
/// Every cursor has a local end; a message cannot consume its neighbour.
priv struct Cursor {
  data : Bytes
  mut pos : Int32
  end : Int32
}

///|
fn cursor(data : Bytes, start : Int32, size : Int32) -> Cursor raise H5Error {
  if start < 0 ||
    size < 0 ||
    start > data.length() ||
    size > data.length() - start {
    raise Invalid("truncated byte range", start)
  }
  { data, pos: start, end: start + size, }
}

///|
fn Cursor::need(self : Cursor, n : Int32) -> Unit raise H5Error {
  if n < 0 || n > self.end - self.pos {
    raise Invalid("truncated field", self.pos)
  }
}

///|
fn Cursor::u8(self : Cursor) -> Int32 raise H5Error {
  self.need(1)
  let v = self.data[self.pos].to_int()
  self.pos += 1
  v
}

///|
fn Cursor::skip(self : Cursor, n : Int32) -> Unit raise H5Error {
  self.need(n)
  self.pos += n
}

///|
fn Cursor::bytes(self : Cursor, n : Int32) -> Bytes raise H5Error {
  self.need(n)
  let out = self.data[self.pos:self.pos + n].to_owned()
  self.pos += n
  out
}

///|
fn Cursor::uint(self : Cursor, width : Int32) -> UInt64 raise H5Error {
  if width != 1 && width != 2 && width != 4 && width != 8 {
    raise Unsupported("integer field width", self.pos)
  }
  self.need(width)
  let mut out = 0UL
  for i = 0; i < width; i = i + 1 {
    out = out | (self.u8().to_uint64() << (i * 8))
  }
  out
}

///|
/// Host indices are deliberately bounded; never truncate 64-bit addresses.
fn Cursor::index(self : Cursor, width : Int32) -> Int32 raise H5Error {
  let at = self.pos
  let n = self.uint(width)
  if n > 2147483647UL {
    raise Limit("file offset/extent exceeds Int range at \{at}")
  }
  n.to_int()
}

///|
/// HDF5's all-ones address is an absent address, not a huge positive index.
fn Cursor::address(
  self : Cursor,
  width : Int32,
  base : Int32,
) -> Int32? raise H5Error {
  let n = self.uint(width)
  let absent = if width == 8 {
    0xffffffffffffffffUL
  } else {
    (1UL << (8 * width)) - 1UL
  }
  if n == absent {
    return None
  }
  if n > 2147483647UL {
    raise Limit("file address exceeds Int range")
  }
  Some(checked_add(base, n.to_int()))
}

///|
fn Cursor::signature(self : Cursor, expected : Bytes) -> Unit raise H5Error {
  let start = self.pos
  if self.bytes(expected.length()) != expected {
    raise Invalid("bad signature", start)
  }
}

///|
priv struct Buffer {
  items : Array[Byte]
}

///|
fn buffer() -> Buffer {
  { items: [], }
}

///|
fn Buffer::length(self : Buffer) -> Int32 {
  self.items.length()
}

///|
fn Buffer::u8(self : Buffer, n : Int32) -> Unit {
  self.items.push(n.to_byte())
}

///|
fn Buffer::uint(self : Buffer, n : UInt64, width : Int32) -> Unit {
  for i = 0; i < width; i = i + 1 {
    self.items.push((n >> (i * 8)).to_byte())
  }
}

///|
fn Buffer::bytes(self : Buffer, data : Bytes) -> Unit {
  for byte in data {
    self.items.push(byte)
  }
}

///|
fn Buffer::zeros(self : Buffer, count : Int32) -> Unit {
  for i = 0; i < count; i = i + 1 {
    self.items.push(0)
  }
}

///|
fn Buffer::finish(self : Buffer) -> Bytes {
  Bytes::from_array(self.items)
}

///|
fn bytes_at(data : Bytes, start : Int32, length : Int32) -> Bytes raise H5Error {
  cursor(data, start, length).bytes(length)
}

///|
test "bounded cursor rejects truncation and 64-bit host overflow" {
  let c = cursor(b"\x01\x02\x03\x04", 0, 4)
  assert_eq(c.uint(2), 513UL)
  assert_eq(c.bytes(2), b"\x03\x04")
  let bad = try {
    ignore(c.u8())
    false
  } catch {
    _ => true
  }
  assert_true(bad)
  assert_eq(cursor(b"\xff\xff\xff\xff", 0, 4).address(4, 0), None)
  assert_true(
    try {
      ignore(cursor(b"\x00\x00\x00\x80", 0, 4).index(4))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "little endian buffer preserves exact unsigned bits" {
  let b = buffer()
  b.uint(0xfedcba9876543210UL, 8)
  assert_eq(cursor(b.finish(), 0, 8).uint(8), 0xfedcba9876543210UL)
}
