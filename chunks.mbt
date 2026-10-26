///|
pub(all) struct ChunkInfo {
  origin : Array[Int]
  address : Int
  stored_bytes : Int
  filter_mask : UInt
} derive(Debug, Eq)
///|
pub extend ChunkInfo with @debug.Debug::{to_repr}
///|
pub extend ChunkInfo with Eq::{equal, not_equal}

///|
fn chunk_key(origin : Array[Int]) -> String { origin.map(n => n.to_string()).join(",") }

///|
fn H5File::chunk_index(self : H5File, info : DatasetInfo) -> Array[ChunkInfo] raise H5Error {
  guard info.storage is Chunked(root, dimensions) else { raise Invalid("dataset is not chunked", 0) }
  guard info.dataspace is Simple(shape) else { raise Invalid("chunked scalar/null", 0) }
  guard root is Some(root) else { return [] }
  let out : Array[ChunkInfo] = []
  let queue = [(root, 0, 256)]
  let seen : Map[Int, Bool] = Map([])
  let origins : Map[String, Bool] = Map([])
  let mut next = 0
  let mut metadata_bytes = 0
  while next < queue.length() {
    let (address, depth, parent_level) = queue[next]
    next += 1
    if depth > self.limits.max_depth || queue.length() > self.limits.max_objects { raise Limit("chunk index traversal") }
    if seen.contains(address) { raise Invalid("cyclic chunk Btree", address) }
    seen[address] = true
    let c = cursor(self.data, address, self.sb.eof - address)
    c.signature(b"TREE")
    if c.u8() != 1 { raise Invalid("not a raw chunk Btree", address) }
    let level = c.u8()
    if level >= parent_level { raise Invalid("chunk tree level does not decrease", address) }
    let count = c.index(2)
    c.skip(2 * self.sb.offset_width)
    let key_size = checked_add(8, checked_mul(dimensions.length(), 8))
    for i = 0; i <= count; i = i + 1 {
      let stored_bytes = c.index(4)
      let mask = c.uint(4).to_uint()
      let origin : Array[Int] = []
      for j = 0; j < dimensions.length(); j = j + 1 { origin.push(c.index(8)) }
      if i == count { break }
      let child = c.address(self.sb.offset_width, self.sb.base).unwrap_or(-1)
      if level > 0 {
        queue.push((child, depth + 1, level))
      } else {
        if stored_bytes <= 0 || stored_bytes > self.limits.max_file_bytes { raise Limit("stored chunk size") }
        if origin.last() != Some(0) { raise Invalid("chunk byte-dimension offset", address) }
        ignore(origin.pop())
        for j = 0; j < shape.length(); j = j + 1 {
          if origin[j] >= shape[j] || origin[j] % dimensions[j] != 0 { raise Invalid("chunk origin outside grid", address) }
        }
        let key = chunk_key(origin)
        if origins.contains(key) { raise Invalid("duplicate chunk origin", address) }
        origins[key] = true
        if out.length() >= self.limits.max_objects { raise Limit("chunk count") }
        ignore(self.range(child, stored_bytes))
        out.push({ origin, address: child, stored_bytes, filter_mask: mask })
      }
    }
    metadata_bytes = checked_add(metadata_bytes, checked_add(24, checked_mul(count + 1, key_size + self.sb.offset_width)))
    if metadata_bytes > self.limits.max_metadata_bytes { raise Limit("chunk index bytes") }
  }
  out
}

///|
pub fn H5File::chunks(self : H5File, path : String) -> Array[ChunkInfo] raise H5Error {
  self.chunk_index(self.dataset_info(path))
}

///|
fn H5File::read_chunked_selection(self : H5File, path : String, info : DatasetInfo, selection : Selection) -> ArrayValue raise H5Error {
  guard info.storage is Chunked(_, dims) else { raise Invalid("not chunked", 0) }
  guard info.dataspace is Simple(shape) else { raise Invalid("chunked scalar/null", 0) }
  let filters = self.filters(path)
  let chunks = self.chunk_index(info)
  let indexed : Map[String, ChunkInfo] = Map([])
  for chunk in chunks { indexed[chunk_key(chunk.origin)] = chunk }
  let decoded : Map[String, Bytes] = Map([])
  let width = info.datatype.width()
  let mut chunk_bytes = 1
  for n in dims { chunk_bytes = checked_mul(chunk_bytes, n) }
  let mut cache_bytes = 0
  let b = buffer()
  let count = selection.result.elements(limits=self.limits)
  for i = 0; i < count; i = i + 1 {
    let mut flat = selection.source_index(i)
    let origin : Array[Int] = Array::make(shape.length(), 0)
    let mut inside = 0
    let mut stride = 1
    for j = shape.length() - 1; j >= 0; j = j - 1 {
      let coordinate = flat % shape[j]
      flat /= shape[j]
      origin[j] = coordinate / dims[j] * dims[j]
      inside = checked_add(inside, checked_mul(coordinate % dims[j], stride))
      stride = checked_mul(stride, dims[j])
    }
    let key = chunk_key(origin)
    let raw = match decoded.get(key) {
      Some(bytes) => Some(bytes)
      None => match indexed.get(key) {
        Some(chunk) => {
          let bytes = decode_filters(self.range(chunk.address, chunk.stored_bytes), filters, chunk.filter_mask, chunk_bytes, width, self.limits)
          cache_bytes = checked_add(cache_bytes, chunk_bytes)
          if cache_bytes > self.limits.max_file_bytes { raise Limit("decoded chunk cache") }
          decoded[key] = bytes
          Some(bytes)
        }
        None => None
      }
    }
    match raw {
      Some(bytes) => b.bytes(bytes_at(bytes, checked_mul(inside, width), width))
      None => b.bytes(info.fill)
    }
  }
  ArrayValue::new(info.datatype, selection.result, b.finish(), limits=self.limits)
}
