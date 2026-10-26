///|
pub(all) struct FilterInfo {
  id : Int32
  optional : Bool
  parameters : Array[Int32]
} derive(Debug, Eq)

///|
pub extend FilterInfo with @debug.Debug::{to_repr}

///|
pub extend FilterInfo with Eq::{equal, not_equal}

///|
fn decode_pipeline(m : Message) -> Array[FilterInfo] raise H5Error {
  let c = cursor(m.bytes, 0, m.bytes.length())
  let version = c.u8()
  let n = c.u8()
  if version != 1 && version != 2 {
    raise Unsupported("filter pipeline version", m.at)
  }
  if n > 32 {
    raise Limit("filter count")
  }
  if version == 1 {
    c.skip(6)
  }
  let out : Array[FilterInfo] = []
  for i = 0; i < n; i = i + 1 {
    let id = c.index(2)
    let name_length = if version == 1 || id >= 256 { c.index(2) } else { 0 }
    let flags = c.index(2)
    if (flags & 0xfffe) != 0 {
      raise Unsupported("filter flags", m.at)
    }
    let parameters = c.index(2)
    if parameters > 1024 {
      raise Limit("filter parameter count")
    }
    c.skip(name_length)
    let values : Array[Int32] = []
    for j = 0; j < parameters; j = j + 1 {
      values.push(c.index(4))
    }
    if version == 1 && parameters % 2 != 0 {
      c.skip(4)
    }
    out.push({ id, optional: (flags & 1) != 0, parameters: values, })
  }
  out
}

///|
pub fn H5File::filters(
  self : H5File,
  path : String,
) -> Array[FilterInfo] raise H5Error {
  let out : Array[FilterInfo] = []
  let mut found = false
  for m in self.messages(self.resolve(path)) {
    if m.kind == 11 {
      if found {
        raise Invalid("duplicate filter pipeline", m.at)
      }
      found = true
      out.append(decode_pipeline(m))
    }
  }
  out
}

///|
fn unshuffle(raw : Bytes, width : Int32) -> Bytes raise H5Error {
  if width <= 0 || raw.length() % width != 0 {
    raise Invalid("shuffle width", 0)
  }
  let elements = raw.length() / width
  let out = Array::make(raw.length(), b'\x00')
  for byte = 0; byte < width; byte = byte + 1 {
    for i = 0; i < elements; i = i + 1 {
      out[i * width + byte] = raw[byte * elements + i]
    }
  }
  Bytes::from_array(out)
}

///|
/// HDF5 sums little-endian 16-bit words, but stores each checksum half big-endian.
fn unfletcher(raw : Bytes) -> Bytes raise H5Error {
  if raw.length() < 4 {
    raise Invalid("short Fletcher32 data", 0)
  }
  let length = raw.length() - 4
  let mut sum1 = 0
  let mut sum2 = 0
  let mut i = 0
  while i < length {
    let word = raw[i].to_int() +
      (if i + 1 < length { raw[i + 1].to_int() << 8 } else { 0 })
    sum1 = (sum1 + word) % 65535
    sum2 = (sum2 + sum1) % 65535
    i += 2
  }
  let actual1 = raw[length].to_int() * 256 + raw[length + 1].to_int()
  let actual2 = raw[length + 2].to_int() * 256 + raw[length + 3].to_int()
  if sum1 != actual1 || sum2 != actual2 {
    raise Invalid("Fletcher32 checksum mismatch", 0)
  }
  raw[:length].to_owned()
}

///|
fn adler(raw : Bytes) -> UInt32 {
  let mut a = 1U
  let mut b = 0U
  for x in raw {
    a = (a + x.to_uint()) % 65521U
    b = (b + a) % 65521U
  }
  (b << 16) | a
}

///|
/// HDF5 filter 1 is zlib-wrapped DEFLATE, despite the user-facing name gzip.
fn inflate_zlib(raw : Bytes, maximum : Int32) -> Bytes raise H5Error {
  if raw.length() < 6 {
    raise Invalid("truncated zlib chunk", 0)
  }
  let cmf = raw[0].to_int()
  let flg = raw[1].to_int()
  if (cmf & 15) != 8 ||
    cmf >> 4 > 7 ||
    (cmf * 256 + flg) % 31 != 0 ||
    (flg & 32) != 0 {
    raise Unsupported("zlib header or preset dictionary", 0)
  }
  let end = raw.length() - 4
  let decoded = @flate.inflate_exact(raw[2:end], max_output=maximum) catch {
    _ => raise Invalid("invalid or oversized DEFLATE chunk", 0)
  }
  let mut checksum = 0U
  for i = end; i < raw.length(); i = i + 1 {
    checksum = (checksum << 8) | raw[i].to_uint()
  }
  if adler(decoded) != checksum {
    raise Invalid("zlib Adler32 mismatch", 0)
  }
  decoded
}

///|
fn decode_filters(
  raw : Bytes,
  filters : Array[FilterInfo],
  mask : UInt32,
  expected : Int32,
  width : Int32,
  limits : Limits,
) -> Bytes raise H5Error {
  if filters.length() < 32 && mask >> filters.length() != 0 {
    raise Invalid("filter mask outside pipeline", 0)
  }
  let ceiling = checked_add(expected, checked_mul(filters.length(), 4))
  if ceiling > limits.max_file_bytes {
    raise Limit("filter workspace")
  }
  let mut decoded = raw
  for i = filters.length() - 1; i >= 0; i = i - 1 {
    if (mask & (1U << i)) != 0 {
      continue
    }
    let f = filters[i]
    decoded = match f.id {
      1 => inflate_zlib(decoded, ceiling)
      2 => {
        if f.parameters.length() != 1 || f.parameters[0] != width {
          raise Invalid("shuffle element width mismatch", 0)
        }
        unshuffle(decoded, width)
      }
      3 => unfletcher(decoded)
      _ => raise Unsupported("active HDF5 filter \{f.id}", 0)
    }
    if decoded.length() > ceiling {
      raise Limit("filter decoded bytes")
    }
  }
  if decoded.length() != expected {
    raise Invalid("decoded chunk size differs", 0)
  }
  decoded
}

///|
test "HDF5 Fletcher32 handles odd bytes and rejects corruption" {
  assert_eq(unfletcher(b"\x01\x02\x03\x02\x04\x04\x05"), b"\x01\x02\x03")
  assert_true(
    try {
      ignore(unfletcher(b"\x01\x02\x04\x02\x04\x04\x05"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "shuffle inversion and per-chunk skipped unknown filters" {
  assert_eq(unshuffle(b"\x01\x03\x02\x04", 2), b"\x01\x02\x03\x04")
  let filters = [{ id: 32000, optional: true, parameters: [], }]
  assert_eq(
    decode_filters(b"abc", filters, 1U, 3, 1, Limits::default()),
    b"abc",
  )
  assert_true(
    try {
      ignore(decode_filters(b"abc", filters, 0U, 3, 1, Limits::default()))
      false
    } catch {
      _ => true
    },
  )
}
