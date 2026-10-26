///|
/// Opening validates the superblock; objects are validated when accessed.
pub struct H5File {
  data : Bytes
  sb : Superblock
  limits : Limits
}

///|
pub fn H5File::open(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> H5File raise H5Error {
  let sb = read_superblock(data, limits)
  let bounded = data[:sb.eof].to_owned()
  ignore(read_messages(bounded, sb, sb.root, limits))
  { data: bounded, sb, limits, }
}

///|
pub fn H5File::superblock_version(self : H5File) -> Int32 {
  self.sb.version
}

///|
fn path_parts(path : String) -> Array[String] raise H5Error {
  if path.contains("\u0000") {
    raise Invalid("NUL in object path", 0)
  }
  let parts : Array[String] = []
  for part in path.split("/") {
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      raise Invalid("parent traversal is not supported", 0)
    }
    parts.push(part.to_owned())
  }
  parts
}

///|
fn H5File::messages(
  self : H5File,
  address : Int32,
) -> Array[Message] raise H5Error {
  if address < self.sb.base || address >= self.sb.eof {
    raise Invalid("object address outside file", address)
  }
  read_messages(self.data, self.sb, address, self.limits)
}

///|
/// Soft links are resolved relative to their containing group. Every hop is bounded.
fn H5File::resolve(self : H5File, path : String) -> Int32 raise H5Error {
  let mut parts = path_parts(path)
  if parts.length() > self.limits.max_depth {
    raise Limit("path depth")
  }
  let mut current = self.sb.root
  let parents : Array[String] = []
  let mut i = 0
  let mut hops = 0
  while i < parts.length() {
    hops += 1
    if hops > self.limits.max_depth {
      raise Limit("link resolution depth")
    }
    let links = group_links(
      self.data,
      self.sb,
      self.messages(current),
      self.limits,
    )
    let mut found : LinkTarget? = None
    for link in links {
      if link.name == parts[i] {
        found = Some(link.target)
        break
      }
    }
    match found {
      Some(Hard(target)) => {
        current = target
        parents.push(parts[i])
        i += 1
      }
      Some(Soft(target)) => {
        let expanded = if target.has_prefix("/") { [] } else { parents.copy() }
        expanded.append(path_parts(target))
        for j = i + 1; j < parts.length(); j = j + 1 {
          expanded.push(parts[j])
        }
        parts = expanded
        parents.clear()
        current = self.sb.root
        i = 0
      }
      None => raise NotFound(path)
    }
  }
  ignore(self.messages(current))
  current
}

///|
pub fn H5File::links(
  self : H5File,
  path~ : String = "/",
) -> Array[Link] raise H5Error {
  group_links(
    self.data,
    self.sb,
    self.messages(self.resolve(path)),
    self.limits,
  )
}

///|
pub fn H5File::object_address(
  self : H5File,
  path : String,
) -> Int32 raise H5Error {
  self.resolve(path)
}

///|
pub(all) struct ObjectEntry {
  path : String
  address : Int32
  dataset : Bool
} derive(Debug, Eq)

///|
pub extend ObjectEntry with @debug.Debug::{to_repr}

///|
pub extend ObjectEntry with Eq::{equal, not_equal}

///|
/// A hard-linked object is listed once, preventing exponential alias walks.
pub fn H5File::walk(self : H5File) -> Array[ObjectEntry] raise H5Error {
  let queue = [("/", self.sb.root, 0)]
  let seen : Map[Int32, Bool] = Map([])
  let out : Array[ObjectEntry] = []
  let mut next = 0
  while next < queue.length() {
    let (path, address, depth) = queue[next]
    next += 1
    if seen.contains(address) {
      continue
    }
    if depth > self.limits.max_depth || out.length() >= self.limits.max_objects {
      raise Limit("object traversal")
    }
    seen[address] = true
    let messages = self.messages(address)
    let dataset = messages.any(m => m.kind == 1)
    out.push({ path, address, dataset, })
    if !dataset {
      for link in group_links(self.data, self.sb, messages, self.limits) {
        if link.target is Hard(target) {
          if queue.length() >= self.limits.max_objects {
            raise Limit("object link traversal")
          }
          let child = (if path == "/" { "" } else { path }) + "/" + link.name
          queue.push((child, target, depth + 1))
        }
      }
    }
  }
  out
}

///|
test "path normalization rejects parent traversal and NUL" {
  assert_eq(path_parts("//a/./b/"), ["a", "b"])
  assert_true(
    try {
      ignore(path_parts("/a/../b"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(path_parts("a\u0000b"))
      false
    } catch {
      _ => true
    },
  )
}
