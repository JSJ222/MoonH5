///|
/// Walk initialized pages of a fixed-extent chunk index.
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
  let page_capacity = 1 << page_bits
  let paged = count > page_capacity
  let pages = if paged { 1 + (count - 1) / page_capacity } else { 1 }
  let bitmap_bytes = if paged { 1 + (pages - 1) / 8 } else { 0 }
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
  let prefix = checked_add(10, self.sb.offset_width)
  let elements = checked_mul(count, entry_size)
  let bytes = checked_add(
    prefix,
    checked_add(
      elements,
      checked_add(bitmap_bytes, if paged { checked_mul(pages, 4) } else { 0 }),
    ),
  )
  if bytes > self.limits.max_metadata_bytes {
    raise Limit("fixed-array metadata bytes")
  }
  self.check_range(address, bytes)
  let checked_prefix = if paged {
    checked_add(prefix, bitmap_bytes)
  } else {
    bytes
  }
  verify_checksum(self.data, address, checked_prefix)
  let c = cursor(self.data, address, checked_prefix - 4)
  c.signature(b"FADB")
  if c.u8() != 0 || c.u8() != client {
    raise Invalid("fixed-array data block client/version", address)
  }
  if c.address(self.sb.offset_width, self.sb.base) != Some(header) {
    raise Invalid("fixed-array header backlink", address)
  }
  let out : Array[ChunkInfo] = []
  let bitmap = c.bytes(bitmap_bytes)
  let mut page_address = checked_add(address, checked_prefix)
  for page = 0; page < pages; page = page + 1 {
    let first = if paged { page * page_capacity } else { 0 }
    let n = if paged { page_capacity.min(count - first) } else { count }
    let entries = if paged {
      let size = checked_add(checked_mul(n, entry_size), 4)
      let at = page_address
      page_address = checked_add(page_address, size)
      if (bitmap[page / 8].to_int() & (128 >> (page % 8))) == 0 {
        continue
      }
      verify_checksum(self.data, at, size)
      cursor(self.data, at, size - 4)
    } else {
      c
    }
    for index = first; index < first + n; index = index + 1 {
      let chunk_address = entries.address(self.sb.offset_width, self.sb.base)
      let stored = if client == 0 {
        raw_size
      } else {
        entries.index(size_width)
      }
      let mask = if client == 0 { 0U } else { entries.uint(4).to_uint() }
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
  }
  out
}
