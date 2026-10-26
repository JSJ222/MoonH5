///|
priv struct Message {
  kind : Int32
  flags : Int32
  bytes : Bytes
  at : Int32
}

///|
fn read_messages(
  data : Bytes,
  sb : Superblock,
  address : Int32,
  limits : Limits,
) -> Array[Message] raise H5Error {
  let c = cursor(data, address, sb.eof - address)
  let first = c.u8()
  let modern = first != 1
  let mut creation = false
  let (start, size) = if !modern {
    if c.u8() != 0 {
      raise Invalid("object header reserved byte", c.pos - 1)
    }
    ignore(c.index(2))
    ignore(c.index(4))
    let n = c.index(4)
    c.skip(4)
    (c.pos, n)
  } else {
    c.pos = address
    c.signature(b"OHDR")
    if c.u8() != 2 {
      raise Unsupported("object header version", address)
    }
    let flags = c.u8()
    if (flags & 0xc0) != 0 {
      raise Unsupported("object header flags", address)
    }
    if (flags & 8) != 0 && (flags & 4) == 0 {
      raise Invalid("indexed order without tracking", address)
    }
    creation = (flags & 4) != 0
    if (flags & 32) != 0 {
      c.skip(16)
    }
    if (flags & 16) != 0 {
      c.skip(4)
    }
    let n = c.index(1 << (flags & 3))
    if n > limits.max_metadata_bytes {
      raise Limit("object header bytes")
    }
    verify_checksum(
      data,
      address,
      checked_add(c.pos - address, checked_add(n, 4)),
    )
    (c.pos, n)
  }
  let ranges = [(start, size)]
  let seen : Map[Int32, Bool] = Map([])
  seen[start] = true
  let messages : Array[Message] = []
  let mut total = 0
  let mut next = 0
  while next < ranges.length() {
    if ranges.length() > limits.max_objects {
      raise Limit("continuation count")
    }
    let (pos, length) = ranges[next]
    next += 1
    total = checked_add(total, length)
    if total > limits.max_metadata_bytes {
      raise Limit("metadata bytes")
    }
    let block = cursor(data, pos, length)
    let prefix = if modern { if creation { 6 } else { 4 } } else { 8 }
    while block.end - block.pos >= prefix {
      let at = block.pos
      let kind = block.index(if modern { 1 } else { 2 })
      let len = block.index(2)
      let flags = block.u8()
      if modern {
        if creation {
          block.skip(2)
        }
      } else {
        block.skip(3)
      }
      if (flags & 2) != 0 {
        raise Unsupported("shared header message", at)
      }
      let bytes = block.bytes(len)
      if kind == 16 {
        let p = cursor(bytes, 0, bytes.length())
        let continuation = p.address(sb.offset_width, sb.base).unwrap_or(-1)
        let length = p.index(sb.size_width)
        if continuation < 0 || seen.contains(continuation) {
          raise Invalid("cyclic or absent continuation", at)
        }
        seen[continuation] = true
        if modern {
          if length < 8 {
            raise Invalid("short continuation", continuation)
          }
          cursor(data, continuation, length).signature(b"OCHK")
          verify_checksum(data, continuation, length)
          ranges.push((continuation + 4, length - 8))
        } else {
          ranges.push((continuation, length))
        }
      } else if kind != 0 {
        messages.push({ kind, flags, bytes, at, })
        if messages.length() > limits.max_objects {
          raise Limit("header message count")
        }
      }
    }
    // Only small zero gaps may remain in a modern header.
    while block.pos < block.end {
      if block.u8() != 0 {
        raise Invalid("nonzero object header gap", block.pos - 1)
      }
    }
  }
  messages
}

///|
fn message(kind : Int32, bytes : Bytes) -> Message {
  { kind, flags: 0, bytes, at: 0, }
}

///|
fn encode_header(
  messages : Array[Message],
  limits : Limits,
) -> Bytes raise H5Error {
  let body = buffer()
  for m in messages {
    if m.kind < 0 || m.kind > 255 || m.bytes.length() > 65535 {
      raise Limit("object message size")
    }
    body.u8(m.kind)
    body.uint(m.bytes.length().to_uint64(), 2)
    body.u8(m.flags)
    body.bytes(m.bytes)
    if body.length() > limits.max_metadata_bytes {
      raise Limit("header size")
    }
  }
  let b = buffer()
  b.bytes(b"OHDR")
  b.u8(2)
  b.u8(2)
  b.uint(body.length().to_uint64(), 4)
  b.bytes(body.finish())
  b.uint(metadata_checksum(b.finish()).to_uint64(), 4)
  b.finish()
}

///|
test "packed modern object header verifies each message boundary" {
  let limits = Limits::default()
  let header = encode_header([message(1, b"abc"), message(12, b"defg")], limits)
  let sb : Superblock = {
    version: 2,
    offset_width: 8,
    size_width: 8,
    base: 0,
    root: 0,
    eof: header.length(),
  }
  let m = read_messages(header, sb, 0, limits)
  assert_eq(m.length(), 2)
  assert_eq(m[1].bytes, b"defg")
  let truncated = header[:header.length() - 1].to_owned()
  assert_true(
    try {
      ignore(read_messages(truncated, sb, 0, limits))
      false
    } catch {
      _ => true
    },
  )
}
