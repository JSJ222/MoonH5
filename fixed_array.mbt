///| The unpaged fixed array covers modern fixed-extent chunked datasets.

///|
/// Paged arrays and extensible arrays remain explicit unsupported profiles.
fn H5File::fixed_array_chunks(
  self : H5File,
  info : DatasetInfo,
) -> Array[ChunkInfo] raise H5Error {
  guard info.storage is FixedArray(header, dims, layout_page_bits) else {
    raise Invalid("not fixed-array storage", 0)
  }
  guard info.dataspace is Simple(shape) else {
    raise Invalid("fixed-array scalar/null", 0)
  }
  guard header is Some(header) else { return [] }
  let h = cursor(self.data, header, self.sb.eof - header)
  h.signature(b"FAHD")
  if h.u8() != 0 {
    raise Unsupported("fixed-array version", header)
  }
  let client = h.u8()
  let entry_size = h.u8()
  let page_bits = h.u8()
  if client > 1 || page_bits != layout_page_bits || page_bits > 30 {
    raise Unsupported("fixed-array client/page configuration", header)
  }
  let count = h.index(self.sb.size_width)
  let data_address = h.address(self.sb.offset_width, self.sb.base)
  h.skip(4)
  verify_checksum(self.data, header, h.pos - header)
  if count > self.limits.max_objects {
    raise Limit("fixed-array entries")
  }
  if count > 1 << page_bits {
    raise Unsupported("paged fixed-array index", header)
  }
  let grid : Array[Int32] = []
  let mut total = 1
  let mut raw_size = info.datatype.width()
  for i = 0; i < shape.length(); i = i + 1 {
    let n = shape[i] / dims[i] + (if shape[i] % dims[i] != 0 { 1 } else { 0 })
    grid.push(n)
    total = checked_mul(total, n)
    raw_size = checked_mul(raw_size, dims[i])
  }
  if count != total {
    raise Unsupported(
      "fixed-array maximum extent differs from current grid", header,
    )
  }
  let size_width = if client == 0 {
    0
  } else {
    entry_size - self.sb.offset_width - 4
  }
  if (client == 0 && entry_size != self.sb.offset_width) ||
    (client == 1 && (size_width < 1 || size_width > 8)) {
    raise Invalid("fixed-array entry size", header)
  }
  guard data_address is Some(address) else { return [] }
  let bytes = checked_add(
    checked_add(10, self.sb.offset_width),
    checked_mul(count, entry_size),
  )
  if bytes > self.limits.max_metadata_bytes {
    raise Limit("fixed-array metadata bytes")
  }
  self.check_range(address, bytes)
  verify_checksum(self.data, address, bytes)
  let c = cursor(self.data, address, bytes - 4)
  c.signature(b"FADB")
  if c.u8() != 0 || c.u8() != client {
    raise Invalid("fixed-array data block client/version", address)
  }
  if c.address(self.sb.offset_width, self.sb.base) != Some(header) {
    raise Invalid("fixed-array header backlink", address)
  }
  let out : Array[ChunkInfo] = []
  for index = 0; index < count; index = index + 1 {
    let chunk_address = c.address(self.sb.offset_width, self.sb.base)
    let stored = if client == 0 { raw_size } else { c.index(size_width) }
    let mask = if client == 0 { 0U } else { c.uint(4).to_uint() }
    guard chunk_address is Some(chunk_address) else { continue }
    if stored <= 0 || stored > self.limits.max_file_bytes {
      raise Limit("fixed-array stored chunk bytes")
    }
    self.check_range(chunk_address, stored)
    let origin = Array::make(shape.length(), 0)
    let mut left = index
    for j = shape.length() - 1; j >= 0; j = j - 1 {
      origin[j] = checked_mul(left % grid[j], dims[j])
      left /= grid[j]
    }
    out.push({
      origin,
      address: chunk_address,
      stored_bytes: stored,
      filter_mask: mask,
    })
  }
  out
}
