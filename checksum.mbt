///| HDF5 metadata checksum: Bob Jenkins' public-domain lookup3 algorithm.
fn rotate(x : UInt, n : Int) -> UInt { (x << n) | (x >> (32 - n)) }

///| The mixing steps are kept explicit to preserve modular UInt arithmetic.
pub fn metadata_checksum(data : Bytes) -> UInt {
  let mut a = 0xdeadbeefU + data.length().reinterpret_as_uint()
  let mut b = a
  let mut c = a
  let mut pos = 0
  while data.length() - pos > 12 {
    for i = 0; i < 4; i = i + 1 {
      a += data[pos + i].to_uint() << (8 * i)
      b += data[pos + 4 + i].to_uint() << (8 * i)
      c += data[pos + 8 + i].to_uint() << (8 * i)
    }
    a -= c; a = a ^ rotate(c, 4); c += b
    b -= a; b = b ^ rotate(a, 6); a += c
    c -= b; c = c ^ rotate(b, 8); b += a
    a -= c; a = a ^ rotate(c, 16); c += b
    b -= a; b = b ^ rotate(a, 19); a += c
    c -= b; c = c ^ rotate(b, 4); b += a
    pos += 12
  }
  let remaining = data.length() - pos
  if remaining == 0 { return c }
  for i = 0; i < remaining; i = i + 1 {
    let x = data[pos + i].to_uint() << (8 * (i % 4))
    if i < 4 { a += x } else if i < 8 { b += x } else { c += x }
  }
  c = c ^ b; c -= rotate(b, 14)
  a = a ^ c; a -= rotate(c, 11)
  b = b ^ a; b -= rotate(a, 25)
  c = c ^ b; c -= rotate(b, 16)
  a = a ^ c; a -= rotate(c, 4)
  b = b ^ a; b -= rotate(a, 14)
  c = c ^ b; c -= rotate(b, 24)
  c
}

///|
fn verify_checksum(data : Bytes, start : Int, size : Int) -> Unit raise H5Error {
  if size < 4 { raise Invalid("checksum block too small", start) }
  let expected = cursor(data, checked_add(start, size - 4), 4).uint(4).to_uint()
  if metadata_checksum(bytes_at(data, start, size - 4)) != expected {
    raise Invalid("metadata checksum mismatch", start)
  }
}

///|
test "lookup3 public known empty vector and block sensitivity" {
  assert_eq(metadata_checksum(b""), 0xdeadbeefU)
  assert_eq(metadata_checksum(b"a"), 0x58d68708U)
  assert_true(metadata_checksum(b"abcdefghijkl") != metadata_checksum(b"abcdefghijkm"))
  let b = buffer()
  b.bytes(b"OHDR example")
  b.uint(metadata_checksum(b.finish()).to_uint64(), 4)
  verify_checksum(b.finish(), 0, b.length())
}
