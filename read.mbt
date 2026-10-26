///|
fn repeated_fill(
  fill : Bytes,
  count : Int32,
  limits : Limits,
) -> Bytes raise H5Error {
  let size = checked_mul(fill.length(), count)
  if size > limits.max_file_bytes {
    raise Limit("fill allocation")
  }
  let b = buffer()
  for i = 0; i < count; i = i + 1 {
    b.bytes(fill)
  }
  b.finish()
}

///|
/// Byte access is bounded by the declared EOF, not just the transport buffer.
fn H5File::range(
  self : H5File,
  address : Int32,
  length : Int32,
) -> Bytes raise H5Error {
  if address < self.sb.base ||
    length < 0 ||
    address > self.sb.eof ||
    length > self.sb.eof - address {
    raise Invalid("raw dataset outside declared file", address)
  }
  bytes_at(self.data, address, length)
}

///|
pub fn H5File::read(self : H5File, path : String) -> ArrayValue raise H5Error {
  let info = self.dataset_info(path)
  let raw = match info.storage {
    Compact(bytes) => bytes
    Contiguous(Some(address), size) => self.range(address, size)
    Contiguous(None, _) =>
      repeated_fill(
        info.fill,
        info.dataspace.elements(limits=self.limits),
        self.limits,
      )
    Chunked(_, _) =>
      return self.read_chunked_selection(
        path,
        info,
        Selection::all(info.dataspace, limits=self.limits),
      )
  }
  ArrayValue::new(info.datatype, info.dataspace, raw, limits=self.limits)
}

///|
test "compact contiguous empty scalar and null datasets retain values" {
  let doc = Document::new()
  doc.add_dataset(
    "/a",
    ArrayValue::from_floats(Simple([2, 2]), [1.25, -2.0, 3.0, 4.5]),
  )
  doc.add_dataset(
    "/b",
    ArrayValue::from_signed(Scalar, [9223372036854775807L]),
    compact=true,
  )
  doc.add_dataset(
    "/empty",
    ArrayValue::new(Unsigned(1, Little), Simple([0, 4]), b""),
  )
  doc.add_dataset("/null", ArrayValue::new(Float(8, Little), Null, b""))
  doc.set_attribute("/a", "unit", ArrayValue::from_strings(Scalar, ["Pa"], 2))
  let f = H5File::open(doc.encode())
  assert_eq(f.read("/a").float_at(3), 4.5)
  assert_eq(f.read("/b").signed_at(0), 9223372036854775807L)
  assert_eq(f.read("/empty").dataspace(), Simple([0, 4]))
  assert_eq(f.read("/null").dataspace(), Null)
  assert_eq(f.attributes(path="/a")[0].value.string_at(0), "Pa")
}
