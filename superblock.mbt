///|
struct Superblock {
  version : Int
  offset_width : Int
  size_width : Int
  base : Int
  eof : Int
  root : Int
}

///|
fn read_superblock(data : Bytes, limits : Limits) -> Superblock raise H5Error {
  limits.validate()
  if data.length() > limits.max_file_bytes { raise Limit("input file size") }
  let magic = b"\x89HDF\r\n\x1a\n"
  let mut at = 0
  while true {
    if at <= data.length() - 8 && data[at:at + 8].to_owned() == magic { break }
    if at == 0 { at = 512 } else {
      if at > data.length() / 2 { raise Invalid("HDF5 signature not found", 0) }
      at *= 2
    }
    if at > data.length() - 8 { raise Invalid("HDF5 signature not found", 0) }
  }
  let c = cursor(data, at, data.length() - at)
  c.signature(magic)
  let version = c.u8()
  let (offset_width, size_width, base, eof, root) = match version {
    0 | 1 => {
      if c.u8() != 0 || c.u8() != 0 || c.u8() != 0 || c.u8() != 0 {
        raise Unsupported("legacy superblock versions", at)
      }
      let ow = c.u8()
      let sw = c.u8()
      if c.u8() != 0 { raise Invalid("reserved superblock field", c.pos - 1) }
      c.skip(4)
      let flags = c.index(4)
      if flags != 0 { raise Unsupported("file consistency flags", at) }
      if version == 1 { c.skip(4) }
      let base = c.index(ow)
      let free = c.address(ow, base)
      let eof = c.index(ow)
      let driver = c.address(ow, base)
      if free != None || driver != None { raise Unsupported("external file driver/free space", at) }
      ignore(c.uint(sw))
      let root = c.address(ow, base).unwrap_or(-1)
      (ow, sw, base, eof, root)
    }
    2 | 3 => {
      let ow = c.u8()
      let sw = c.u8()
      let flags = c.u8()
      if flags != 0 { raise Unsupported("file open for write or SWMR", at) }
      let base = c.index(ow)
      let extension = c.address(ow, base)
      let eof = c.index(ow)
      let root = c.address(ow, base).unwrap_or(-1)
      if extension != None { raise Unsupported("superblock extension", at) }
      c.skip(4)
      verify_checksum(data, at, c.pos - at)
      (ow, sw, base, eof, root)
    }
    _ => raise Unsupported("superblock version", at)
  }
  if offset_width != 2 && offset_width != 4 && offset_width != 8 {
    raise Unsupported("offset width", at)
  }
  if size_width != 2 && size_width != 4 && size_width != 8 {
    raise Unsupported("length width", at)
  }
  if base != at { raise Unsupported("relocated base address", at) }
  if eof > data.length() || eof <= root || root < base { raise Invalid("file/root bounds", at) }
  { version, offset_width, size_width, base, eof, root }
}

///|
fn write_superblock(root : Int, eof : Int) -> Bytes {
  let b = buffer()
  b.bytes(b"\x89HDF\r\n\x1a\n")
  b.u8(2)
  b.u8(8)
  b.u8(8)
  b.u8(0)
  b.uint(0UL, 8)
  b.uint(0xffffffffffffffffUL, 8)
  b.uint(eof.to_uint64(), 8)
  b.uint(root.to_uint64(), 8)
  b.uint(metadata_checksum(b.finish()).to_uint64(), 4)
  b.finish()
}

///|
test "superblock checksum and declared EOF are enforced" {
  let b = buffer()
  b.bytes(write_superblock(48, 49))
  b.u8(0)
  let sb = read_superblock(b.finish(), Limits::default())
  assert_eq(sb.root, 48)
  assert_eq(sb.version, 2)
  assert_eq(sb.eof, 49)
  let broken = b.finish().to_array()
  broken[16] = 1
  assert_true(try { ignore(read_superblock(Bytes::from_array(broken), Limits::default())); false } catch { _ => true })
}
