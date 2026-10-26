///|
pub enum LinkTarget {
  Hard(Int32)
  Soft(String)
} derive(Debug, Eq)

///|
pub extend LinkTarget with @debug.Debug::{to_repr}

///|
pub extend LinkTarget with Eq::{equal, not_equal}

///|
pub(all) struct Link {
  name : String
  target : LinkTarget
} derive(Debug, Eq)

///|
pub extend Link with @debug.Debug::{to_repr}

///|
pub extend Link with Eq::{equal, not_equal}

///|
fn text(bytes : Bytes, at : Int32) -> String raise H5Error {
  @utf8.decode(bytes, ignore_bom=false) catch {
    _ => raise Invalid("invalid UTF8 name", at)
  }
}

///|
fn valid_name(name : String) -> Unit raise H5Error {
  if name == "" ||
    name == "." ||
    name == ".." ||
    name.contains("/") ||
    name.contains("\u0000") {
    raise Invalid("invalid link/attribute name", 0)
  }
}

///|
fn decode_link(m : Message, sb : Superblock) -> Link raise H5Error {
  let c = cursor(m.bytes, 0, m.bytes.length())
  if c.u8() != 1 {
    raise Unsupported("link version", m.at)
  }
  let flags = c.u8()
  if (flags & 0xe0) != 0 {
    raise Unsupported("link flags", m.at)
  }
  let kind = if (flags & 8) != 0 { c.u8() } else { 0 }
  if (flags & 4) != 0 {
    c.skip(8)
  }
  let charset = if (flags & 16) != 0 { c.u8() } else { 0 }
  if charset > 1 {
    raise Unsupported("name charset", m.at)
  }
  let n = c.index(1 << (flags & 3))
  let raw = c.bytes(n)
  if charset == 0 {
    for x in raw {
      if x > 127 {
        raise Invalid("nonASCII link name", m.at)
      }
    }
  }
  let name = text(raw, m.at)
  valid_name(name)
  let target = match kind {
    0 => Hard(c.address(sb.offset_width, sb.base).unwrap_or(-1))
    1 => {
      let n = c.index(2)
      Soft(text(c.bytes(n), m.at))
    }
    _ => raise Unsupported("external or user-defined link", m.at)
  }
  if c.pos != c.end {
    raise Invalid("extra link data", m.at)
  }
  { name, target, }
}

///|
fn encode_link(name : String, target : Int32) -> Message raise H5Error {
  valid_name(name)
  let raw = @utf8.encode(name)
  if raw.length() > 65500 {
    raise Limit("link name length")
  }
  let b = buffer()
  b.u8(1)
  b.u8(17)
  b.u8(1)
  b.uint(raw.length().to_uint64(), 2)
  b.bytes(raw)
  b.uint(target.to_uint64(), 8)
  message(6, b.finish())
}

///|
fn cstring(data : Bytes, at : Int32, end : Int32) -> String raise H5Error {
  let c = cursor(data, at, end - at)
  while c.pos < c.end {
    if c.u8() == 0 {
      return text(bytes_at(data, at, c.pos - at - 1), at)
    }
  }
  raise Invalid("unterminated heap string", at)
}

///|
/// Follow only child pointers; sibling pointers are not needed to enumerate.
fn legacy_links(
  data : Bytes,
  sb : Superblock,
  m : Message,
  limits : Limits,
) -> Array[Link] raise H5Error {
  let p = cursor(m.bytes, 0, m.bytes.length())
  let tree = p.address(sb.offset_width, sb.base).unwrap_or(-1)
  let heap = p.address(sb.offset_width, sb.base).unwrap_or(-1)
  let h = cursor(data, heap, sb.eof - heap)
  h.signature(b"HEAP")
  if h.u8() != 0 {
    raise Unsupported("local heap version", heap)
  }
  h.skip(3)
  let heap_size = h.index(sb.size_width)
  ignore(h.uint(sb.size_width))
  let heap_data = h.address(sb.offset_width, sb.base).unwrap_or(-1)
  if heap_size > limits.max_metadata_bytes {
    raise Limit("local heap size")
  }
  ignore(cursor(data, heap_data, heap_size))
  let heap_end = checked_add(heap_data, heap_size)
  let queue = [(tree, 0)]
  let seen : Map[Int32, Bool] = Map([])
  let out : Array[Link] = []
  let mut next = 0
  while next < queue.length() {
    let (address, depth) = queue[next]
    next += 1
    if depth > limits.max_depth || queue.length() > limits.max_objects {
      raise Limit("group Btree traversal")
    }
    if seen.contains(address) {
      raise Invalid("cyclic group Btree", address)
    }
    seen[address] = true
    let c = cursor(data, address, sb.eof - address)
    c.signature(b"TREE")
    if c.u8() != 0 {
      raise Invalid("not a group Btree", address)
    }
    let level = c.u8()
    let count = c.index(2)
    c.skip(2 * sb.offset_width)
    for i = 0; i < count; i = i + 1 {
      ignore(c.uint(sb.size_width))
      let child = c.address(sb.offset_width, sb.base).unwrap_or(-1)
      if level > 0 {
        queue.push((child, depth + 1))
        continue
      }
      let leaf = cursor(data, child, sb.eof - child)
      leaf.signature(b"SNOD")
      if leaf.u8() != 1 || leaf.u8() != 0 {
        raise Invalid("symbol node version", child)
      }
      let entries = leaf.index(2)
      for j = 0; j < entries; j = j + 1 {
        if out.length() >= limits.max_objects {
          raise Limit("group links")
        }
        let offset = leaf.index(sb.offset_width)
        let obj = leaf.address(sb.offset_width, sb.base).unwrap_or(-1)
        let cache = leaf.index(4)
        leaf.skip(4)
        let scratch = leaf.bytes(16)
        if offset >= heap_size {
          raise Invalid("heap name offset", child)
        }
        let name = cstring(data, checked_add(heap_data, offset), heap_end)
        valid_name(name)
        let target = match cache {
          0 | 1 => Hard(obj)
          2 => {
            let soft = cursor(scratch, 0, scratch.length()).index(4)
            if soft >= heap_size {
              raise Invalid("heap soft link offset", child)
            }
            Soft(cstring(data, checked_add(heap_data, soft), heap_end))
          }
          _ => raise Unsupported("symbol cache type", child)
        }
        out.push({ name, target, })
      }
    }
    ignore(c.uint(sb.size_width))
  }
  out
}

///|
fn group_links(
  data : Bytes,
  sb : Superblock,
  messages : Array[Message],
  limits : Limits,
) -> Array[Link] raise H5Error {
  let out : Array[Link] = []
  let names : Map[String, Bool] = Map([])
  for m in messages {
    match m.kind {
      6 => out.push(decode_link(m, sb))
      17 => out.append(legacy_links(data, sb, m, limits))
      2 => {
        let c = cursor(m.bytes, 0, m.bytes.length())
        if c.u8() != 0 {
          raise Unsupported("link info version", m.at)
        }
        let flags = c.u8()
        if flags > 3 {
          raise Unsupported("link info flags", m.at)
        }
        if (flags & 1) != 0 {
          c.skip(8)
        }
        if c.address(sb.offset_width, sb.base) != None ||
          c.address(sb.offset_width, sb.base) != None {
          raise Unsupported("dense group fractal heap/Btree", m.at)
        }
      }
      1 | 3 | 8 => raise Invalid("dataset is not a group", m.at)
      _ =>
        if (m.flags & 128) != 0 &&
          m.kind != 10 &&
          m.kind != 12 &&
          m.kind != 21 &&
          m.kind != 22 {
          raise Unsupported("mandatory group message", m.at)
        }
    }
    if out.length() > limits.max_objects {
      raise Limit("group links")
    }
  }
  for link in out {
    if names.contains(link.name) {
      raise Invalid("duplicate group link", 0)
    }
    names[link.name] = true
  }
  out
}

///|
test "compact links preserve UTF8 names and exact addresses" {
  let sb : Superblock = {
    version: 2,
    offset_width: 8,
    size_width: 8,
    base: 0,
    root: 0,
    eof: 1000,
  }
  let m = encode_link("实验", 512)
  assert_eq(decode_link(m, sb), { name: "实验", target: Hard(512), })
  assert_true(
    try {
      ignore(encode_link("a/b", 0))
      false
    } catch {
      _ => true
    },
  )
}
