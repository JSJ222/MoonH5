///|
fn Document::header(
  self : Document,
  path : String,
  addresses : Map[String, Int32],
  raw_addresses : Map[String, Int32],
) -> Bytes raise H5Error {
  guard self.nodes.get(path) is Some(node) else { raise NotFound(path) }
  let messages : Array[Message] = []
  match node.value {
    Some(value) => {
      messages.push(message(1, value.space.encode(self.limits)))
      messages.push(message(3, value.dtype.encode()))
      // Defined default fill, late allocation, fill on allocation.
      messages.push(message(5, b"\x02\x02\x02\x01\x00\x00\x00\x00"))
      let layout = buffer()
      layout.u8(3)
      if node.compact {
        layout.u8(0)
        layout.uint(value.raw.length().to_uint64(), 2)
        layout.bytes(value.raw)
      } else {
        layout.u8(1)
        layout.uint(
          if value.raw.length() == 0 {
            0xffffffffffffffffUL
          } else {
            raw_addresses.get(path).unwrap_or(0).to_uint64()
          },
          8,
        )
        layout.uint(value.raw.length().to_uint64(), 8)
      }
      messages.push(message(8, layout.finish()))
    }
    None => {
      let info = buffer()
      info.u8(0)
      info.u8(0)
      info.uint(0xffffffffffffffffUL, 8)
      info.uint(0xffffffffffffffffUL, 8)
      messages.push(message(2, info.finish()))
      messages.push(message(10, b"\x00\x01\xff\xff\xff\xff"))
      let children : Array[(String, String)] = []
      for child in self.node_paths() {
        if child == "/" {
          continue
        }
        let (parent, name) = parent_path(child)
        if parent == path {
          children.push((name, child))
        }
      }
      for linkpath, target in self.aliases {
        let (parent, name) = parent_path(linkpath)
        if parent == path {
          children.push((name, target))
        }
      }
      children.sort_by((a, b) => a.0.compare(b.0))
      for (name, target) in children {
        messages.push(encode_link(name, addresses.get(target).unwrap_or(0)))
      }
    }
  }
  let attributes = node.attributes.copy()
  attributes.sort_by((a, b) => a.name.compare(b.name))
  for attribute in attributes {
    messages.push(encode_attribute(attribute, self.limits))
  }
  let mut references = 1
  for _, target in self.aliases {
    if target == path {
      references += 1
    }
  }
  let refcount = buffer()
  refcount.u8(0)
  refcount.uint(references.to_uint64(), 4)
  messages.push(message(22, refcount.finish()))
  encode_header(messages, self.limits)
}

///|
/// Deterministic two-pass layout; raw offsets never depend on payload contents.
pub fn Document::encode(self : Document) -> Bytes raise H5Error {
  let paths = self.node_paths()
  let addresses : Map[String, Int32] = Map([])
  let raw_addresses : Map[String, Int32] = Map([])
  let sizes : Map[String, Int32] = Map([])
  let mut offset = 48
  for path in paths {
    let size = self.header(path, addresses, raw_addresses).length()
    addresses[path] = offset
    sizes[path] = size
    offset = checked_add(offset, size)
    if offset > self.limits.max_file_bytes {
      raise Limit("output metadata size")
    }
  }
  offset = checked_add(offset, (8 - offset % 8) % 8)
  let data_start = offset
  for path in paths {
    let node = self.nodes.get(path).unwrap()
    if node.value is Some(value) && !node.compact {
      raw_addresses[path] = offset
      offset = checked_add(offset, value.raw.length())
      if offset > self.limits.max_file_bytes {
        raise Limit("output file size")
      }
    }
  }
  if offset > self.limits.max_file_bytes {
    raise Limit("output file size")
  }
  let out = buffer()
  out.bytes(write_superblock(addresses.get("/").unwrap(), offset))
  for path in paths {
    let header = self.header(path, addresses, raw_addresses)
    if header.length() != sizes.get(path).unwrap() {
      raise Invalid("unstable header layout", out.length())
    }
    out.bytes(header)
  }
  out.zeros(data_start - out.length())
  for path in paths {
    let node = self.nodes.get(path).unwrap()
    if node.value is Some(value) && !node.compact {
      out.bytes(value.raw)
    }
  }
  out.finish()
}

///|
test "writer produces traversable deterministic files including hard-link cycles" {
  let doc = Document::new()
  doc.add_group("/run")
  doc.add_dataset(
    "/run/samples",
    ArrayValue::from_signed(Simple([2]), [5L, 9L]),
  )
  doc.add_hard_link("/again", "/run/samples")
  doc.add_hard_link("/run/root", "/")
  let bytes = doc.encode()
  assert_eq(bytes, doc.encode())
  let file = H5File::open(bytes)
  assert_eq(file.walk().length(), 3)
  assert_eq(file.object_address("/again"), file.object_address("/run/samples"))
  assert_eq(file.dataset_info("/again").dataspace, Simple([2]))
}
