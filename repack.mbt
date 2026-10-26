///| Rebuilds supported data semantically, not byte-for-byte. Unsupported

///|
/// attributes and storage encodings fail rather than silently disappearing.
pub fn H5File::to_document(self : H5File) -> Document raise H5Error {
  let doc = Document::new(limits=self.limits)
  let entries = self.walk()
  let names : Map[Int32, String] = Map([])
  let mut retained = 0
  for entry in entries {
    names[entry.address] = entry.path
    if entry.path != "/" {
      if entry.dataset {
        let value = self.read(entry.path)
        retained = checked_add(retained, value.raw.length())
        if retained > self.limits.max_file_bytes {
          raise Limit("repack retained bytes")
        }
        doc.add_dataset(entry.path, value)
      } else {
        doc.add_group(entry.path)
      }
    }
    for attribute in self.attributes(path=entry.path) {
      retained = checked_add(retained, attribute.value.raw.length())
      if retained > self.limits.max_file_bytes {
        raise Limit("repack retained bytes")
      }
      doc.set_attribute(entry.path, attribute.name, attribute.value)
    }
  }
  for entry in entries {
    if entry.dataset {
      continue
    }
    for link in self.links(path=entry.path) {
      let path = (if entry.path == "/" { "" } else { entry.path }) +
        "/" +
        link.name
      match link.target {
        Hard(address) => {
          guard names.get(address) is Some(target) else {
            raise Invalid("unvisited hard link target", address)
          }
          if path != target {
            doc.add_hard_link(path, target)
          }
        }
        Soft(target) => doc.add_soft_link(path, target)
      }
    }
  }
  doc
}

///|
test "repack preserves soft links aliases attributes and cyclic groups" {
  let doc = Document::new()
  doc.add_group("/g")
  doc.add_dataset(
    "/g/data",
    ArrayValue::from_signed(Simple([2]), [3L, 4L]),
    compact=true,
  )
  doc.add_hard_link("/g/root", "/")
  doc.add_hard_link("/same", "/g/data")
  doc.add_soft_link("/g/relative", "data")
  doc.add_soft_link("/absolute", "/g/data")
  doc.add_soft_link("/dangling", "/absent")
  doc.set_attribute(
    "/g/data",
    "unit",
    ArrayValue::from_strings(Scalar, ["K"], 1),
  )
  let file = H5File::open(doc.encode())
  assert_eq(file.read("/g/relative").signed_at(1), 4L)
  let copy = H5File::open(file.to_document().encode())
  assert_eq(copy.read("/absolute").signed_at(0), 3L)
  assert_eq(copy.object_address("/same"), copy.object_address("/g/data"))
  assert_eq(copy.walk().length(), 3)
  assert_eq(copy.attributes(path="/g/data")[0].value.string_at(0), "K")
  assert_true(
    try {
      ignore(copy.read("/dangling"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "soft link cycles terminate at a depth limit" {
  let doc = Document::new()
  doc.add_soft_link("/a", "/b")
  doc.add_soft_link("/b", "/a")
  let f = H5File::open(doc.encode())
  assert_true(
    try {
      ignore(f.object_address("/a"))
      false
    } catch {
      _ => true
    },
  )
}
