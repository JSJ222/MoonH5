///|
fn H5File::direct_chunks(
  self : H5File,
  info : DatasetInfo,
) -> Array[ChunkInfo] raise H5Error {
  guard info.dataspace is Simple(shape) else {
    raise Invalid("direct chunks require simple dataspace", 0)
  }
  match info.storage {
    SingleChunk(address, dims, stored, mask) => {
      let mut raw_size = 1
      for i = 0; i < shape.length(); i = i + 1 {
        if shape[i] > dims[i] {
          raise Invalid("single chunk extent", 0)
        }
      }
      for n in dims {
        raw_size = checked_mul(raw_size, n)
      }
      guard address is Some(at) else { return [] }
      let bytes = stored.unwrap_or(raw_size)
      if bytes <= 0 || bytes > self.limits.max_file_bytes {
        raise Limit("single stored chunk bytes")
      }
      self.check_range(at, bytes)
      [
        {
          origin: Array::make(shape.length(), 0),
          address: at,
          stored_bytes: bytes,
          filter_mask: mask,
        },
      ]
    }
    ImplicitChunks(address, dims) => {
      guard address is Some(at) else { return [] }
      let grid = shape.mapi((i, n) => {
        n / dims[i] + (if n % dims[i] == 0 { 0 } else { 1 })
      })
      let mut count = 1
      let mut bytes = 1
      for n in grid {
        count = checked_mul(count, n)
      }
      for n in dims {
        bytes = checked_mul(bytes, n)
      }
      if count > self.limits.max_objects {
        raise Limit("implicit chunk count")
      }
      self.check_range(at, checked_mul(count, bytes))
      Array::makei(count, i => {
        let origin = Array::make(shape.length(), 0)
        let mut remaining = i
        for j = shape.length() - 1; j >= 0; j = j - 1 {
          origin[j] = remaining % grid[j] * dims[j]
          remaining /= grid[j]
        }
        {
          origin,
          address: at + i * bytes,
          stored_bytes: bytes,
          filter_mask: 0U,
        }
      })
    }
    _ => raise Invalid("not direct chunk storage", 0)
  }
}
