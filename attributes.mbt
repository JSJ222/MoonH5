///|
pub(all) struct Attribute {
  name : String
  value : ArrayValue
} derive(Debug)

///|
pub extend Attribute with @debug.Debug::{to_repr}

///|
fn decode_attribute(
  m : Message,
  sb : Superblock,
  limits : Limits,
) -> Attribute raise H5Error {
  let c = cursor(m.bytes, 0, m.bytes.length())
  let version = c.u8()
  if version < 1 || version > 3 {
    raise Unsupported("attribute version", m.at)
  }
  let flags = c.u8()
  if flags != 0 {
    raise Unsupported("shared attribute datatype/dataspace", m.at)
  }
  let namesize = c.index(2)
  let typesize = c.index(2)
  let spacesize = c.index(2)
  let charset = if version == 3 { c.u8() } else { 0 }
  if charset > 1 {
    raise Unsupported("attribute charset", m.at)
  }
  let rawname = c.bytes(namesize)
  if namesize == 0 || rawname[namesize - 1] != 0 {
    raise Invalid("attribute name terminator", m.at)
  }
  let name = text(rawname[:namesize - 1].to_owned(), m.at)
  if name == "" || name.contains("\u0000") {
    raise Invalid("invalid attribute name", m.at)
  }
  if version == 1 {
    c.skip((8 - namesize % 8) % 8)
  }
  let typedata = c.bytes(typesize)
  let dtype = decode_type(cursor(typedata, 0, typedata.length()))
  if version == 1 {
    c.skip((8 - typesize % 8) % 8)
  }
  let spacedata = c.bytes(spacesize)
  let space = decode_space(
    cursor(spacedata, 0, spacedata.length()),
    sb.size_width,
    limits,
  )
  if version == 1 {
    c.skip((8 - spacesize % 8) % 8)
  }
  let size = checked_mul(dtype.width(), space.elements(limits~))
  if size > limits.max_metadata_bytes {
    raise Limit("attribute bytes")
  }
  let value = ArrayValue::new(dtype, space, c.bytes(size), limits~)
  { name, value, }
}

///|
fn encode_attribute(
  attribute : Attribute,
  limits : Limits,
) -> Message raise H5Error {
  let name = attribute.name
  if name == "" || name.contains("\u0000") {
    raise Invalid("invalid attribute name", 0)
  }
  let rawname = @utf8.encode(name)
  let dtype = attribute.value.dtype.encode()
  let space = attribute.value.space.encode(limits)
  if dtype.length() > 65535 ||
    space.length() > 65535 ||
    rawname.length() > 65534 ||
    attribute.value.raw.length() > limits.max_metadata_bytes {
    raise Limit("attribute length")
  }
  let b = buffer()
  b.u8(3)
  b.u8(0)
  b.uint((rawname.length() + 1).to_uint64(), 2)
  b.uint(dtype.length().to_uint64(), 2)
  b.uint(space.length().to_uint64(), 2)
  b.u8(1)
  b.bytes(rawname)
  b.u8(0)
  b.bytes(dtype)
  b.bytes(space)
  b.bytes(attribute.value.raw)
  message(12, b.finish())
}

///|
pub fn H5File::attributes(
  self : H5File,
  path~ : String = "/",
) -> Array[Attribute] raise H5Error {
  let out : Array[Attribute] = []
  let names : Map[String, Bool] = Map([])
  for m in self.messages(self.resolve(path)) {
    if m.kind == 12 {
      let attr = decode_attribute(m, self.sb, self.limits)
      if names.contains(attr.name) {
        raise Invalid("duplicate attribute name", m.at)
      }
      names[attr.name] = true
      out.push(attr)
    } else if m.kind == 21 {
      let c = cursor(m.bytes, 0, m.bytes.length())
      if c.u8() != 0 {
        raise Unsupported("attribute info version", m.at)
      }
      let flags = c.u8()
      if flags > 3 {
        raise Unsupported("attribute info flags", m.at)
      }
      if (flags & 1) != 0 {
        c.skip(2)
      }
      if c.address(self.sb.offset_width, self.sb.base) != None ||
        c.address(self.sb.offset_width, self.sb.base) != None {
        raise Unsupported("dense attributes", m.at)
      }
    }
  }
  out
}

///|
test "inline attributes roundtrip UTF8 and exact array types" {
  let a : Attribute = {
    name: "单位/name",
    value: ArrayValue::from_strings(Scalar, ["m/s"], 8),
  }
  let limits = Limits::default()
  let sb : Superblock = {
    version: 2,
    offset_width: 8,
    size_width: 8,
    base: 0,
    root: 0,
    eof: 0,
  }
  let decoded = decode_attribute(encode_attribute(a, limits), sb, limits)
  assert_eq(decoded.name, a.name)
  assert_eq(decoded.value.string_at(0), "m/s")
}
