///|
struct BuildNode {
  value : ArrayValue?
  compact : Bool
  attributes : Array[Attribute]
}

///|
/// A new file model; it never modifies an existing HDF5 byte buffer in place.
pub struct Document {
  nodes : Map[String, BuildNode]
  aliases : Map[String, String]
  limits : Limits
}

///|
pub fn Document::new(
  limits~ : Limits = Limits::default(),
) -> Document raise H5Error {
  limits.validate()
  {
    nodes: Map([("/", { value: None, compact: false, attributes: [], })]),
    aliases: Map([]),
    limits,
  }
}

///|
fn canonical_path(path : String) -> String raise H5Error {
  let parts = path_parts(path)
  if parts.is_empty() {
    "/"
  } else {
    "/" + parts.join("/")
  }
}

///|
fn parent_path(path : String) -> (String, String) raise H5Error {
  let parts = path_parts(path)
  guard parts.last() is Some(name) else {
    raise Invalid("root has no parent", 0)
  }
  ignore(parts.pop())
  (if parts.is_empty() { "/" } else { "/" + parts.join("/") }, name)
}

///|
fn Document::reserve(self : Document, path : String) -> Unit raise H5Error {
  if self.nodes.contains(path) || self.aliases.contains(path) {
    raise Invalid("object path already exists", 0)
  }
  let parts = path_parts(path)
  if parts.length() > self.limits.max_depth {
    raise Limit("object path depth")
  }
  if self.nodes.length() + self.aliases.length() >= self.limits.max_objects {
    raise Limit("document objects")
  }
  let (parent, _) = parent_path(path)
  guard self.nodes.get(parent) is Some(node) else { raise NotFound(parent) }
  if node.value is Some(_) {
    raise Invalid("parent is a dataset", 0)
  }
}

///|
/// Parent groups must exist. Failure leaves the document unchanged.
pub fn Document::add_group(
  self : Document,
  path : String,
) -> Unit raise H5Error {
  let path = canonical_path(path)
  self.reserve(path)
  self.nodes[path] = { value: None, compact: false, attributes: [], }
}

///|
pub fn Document::add_dataset(
  self : Document,
  path : String,
  value : ArrayValue,
  compact~ : Bool = false,
) -> Unit raise H5Error {
  let path = canonical_path(path)
  self.reserve(path)
  ignore(
    ArrayValue::new(value.dtype, value.space, value.raw, limits=self.limits),
  )
  if compact && value.raw.length() > 65000 {
    raise Limit("compact data must fit a header message")
  }
  self.nodes[path] = { value: Some(value), compact, attributes: [], }
}

///|
/// Targets are existing real objects, not other aliases. Cyclic group links are valid.
pub fn Document::add_hard_link(
  self : Document,
  path : String,
  target : String,
) -> Unit raise H5Error {
  let path = canonical_path(path)
  let target = canonical_path(target)
  self.reserve(path)
  if !self.nodes.contains(target) {
    raise NotFound(target)
  }
  self.aliases[path] = target
}

///|
pub fn Document::set_attribute(
  self : Document,
  path : String,
  name : String,
  value : ArrayValue,
) -> Unit raise H5Error {
  let path = canonical_path(path)
  guard self.nodes.get(path) is Some(node) else { raise NotFound(path) }
  let attribute : Attribute = { name, value, }
  ignore(
    ArrayValue::new(value.dtype, value.space, value.raw, limits=self.limits),
  )
  ignore(encode_attribute(attribute, self.limits))
  for i = 0; i < node.attributes.length(); i = i + 1 {
    if node.attributes[i].name == name {
      node.attributes[i] = attribute
      return
    }
  }
  if node.attributes.length() >= self.limits.max_objects {
    raise Limit("attribute count")
  }
  node.attributes.push(attribute)
}

///|
fn Document::node_paths(self : Document) -> Array[String] {
  let paths = self.nodes.keys().collect()
  paths.sort()
  paths
}

///|
test "document mutations validate parents and fail atomically" {
  let doc = Document::new()
  doc.add_group("/run")
  let v = ArrayValue::from_signed(Scalar, [42L])
  doc.add_dataset("run/value", v)
  assert_true(
    try {
      doc.add_group("/missing/child")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      doc.add_group("/run/value/child")
      false
    } catch {
      _ => true
    },
  )
  doc.set_attribute("/run", "units", ArrayValue::from_strings(Scalar, ["K"], 1))
  assert_eq(doc.node_paths(), ["/", "/run", "/run/value"])
}
