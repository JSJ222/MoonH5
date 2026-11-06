///|
pub(all) struct ChunkOptions {
  shape : Array[Int32]
  gzip : Int32?
  shuffle : Bool
  fletcher32 : Bool
}

///|
pub fn ChunkOptions::new(
  shape : Array[Int32],
  gzip~ : Int32? = None,
  shuffle~ : Bool = false,
  fletcher32~ : Bool = false,
) -> ChunkOptions {
  { shape: shape.copy(), gzip, shuffle, fletcher32, }
}

///|
fn ChunkOptions::validate(
  self : ChunkOptions,
  value : ArrayValue,
  limits : Limits,
) -> Unit raise H5Error {
  guard value.space is Simple(dims) else {
    raise Invalid("chunked writer requires simple dataspace", 0)
  }
  if dims.is_empty() || dims.length() != self.shape.length() {
    raise Invalid("chunk shape rank", 0)
  }
  let mut bytes = value.dtype.width()
  let mut count = 1
  for i, n in self.shape {
    if n < 1 || dims[i] < 1 || n > dims[i] {
      raise Invalid("chunk shape must fit positive fixed extent", 0)
    }
    bytes = checked_mul(bytes, n)
    count = checked_mul(
      count,
      dims[i] / n + (if dims[i] % n == 0 { 0 } else { 1 }),
    )
  }
  if bytes > limits.max_file_bytes || count > limits.max_objects {
    raise Limit("chunk write count/bytes")
  }
  if self.gzip is Some(level) && (level < 0 || level > 9) {
    raise Invalid("gzip level must be 0..9", 0)
  }
}

///|
fn ChunkOptions::pipeline(
  self : ChunkOptions,
  width : Int32,
) -> Array[FilterInfo] {
  let filters : Array[FilterInfo] = []
  if self.shuffle {
    filters.push({ id: 2, optional: true, parameters: [width], })
  }
  if self.gzip is Some(level) {
    filters.push({ id: 1, optional: true, parameters: [level], })
  }
  if self.fletcher32 {
    filters.push({ id: 3, optional: false, parameters: [], })
  }
  filters
}

///|
fn encode_pipeline(filters : Array[FilterInfo]) -> Bytes {
  let b = buffer()
  b.u8(2)
  b.u8(filters.length())
  for f in filters {
    b.uint(f.id.to_uint64(), 2)
    b.uint(if f.optional { 1UL } else { 0UL }, 2)
    b.uint(f.parameters.length().to_uint64(), 2)
    for p in f.parameters {
      b.uint(p.to_uint64(), 4)
    }
  }
  b.finish()
}

///|
fn encode_filters(
  raw : Bytes,
  options : ChunkOptions,
  width : Int32,
) -> Bytes raise H5Error {
  if width <= 0 || raw.length() % width != 0 {
    raise Invalid("filter element width", 0)
  }
  let mut result = raw
  if options.shuffle {
    let n = raw.length() / width
    let shuffled = Array::make(raw.length(), b'\x00')
    for i = 0; i < n; i = i + 1 {
      for j = 0; j < width; j = j + 1 {
        shuffled[j * n + i] = raw[i * width + j]
      }
    }
    result = Bytes::from_array(shuffled)
  }
  if options.gzip is Some(level) {
    let compressed = @flate.deflate_all(result[:], level~)
    let b = buffer()
    b.u8(0x78)
    b.u8(0x9c)
    b.bytes(compressed)
    let checksum = adler(result)
    for i = 3; i >= 0; i = i - 1 {
      b.u8((checksum >> (8 * i)).reinterpret_as_int() & 255)
    }
    result = b.finish()
  }
  if options.fletcher32 {
    let mut a = 0
    let mut b = 0
    let mut i = 0
    while i < result.length() {
      let word = result[i].to_int() +
        (if i + 1 < result.length() { result[i + 1].to_int() << 8 } else { 0 })
      a = (a + word) % 65535
      b = (b + a) % 65535
      i += 2
    }
    let out = buffer()
    out.bytes(result)
    out.u8(a >> 8)
    out.u8(a & 255)
    out.u8(b >> 8)
    out.u8(b & 255)
    result = out.finish()
  }
  result
}

///|
priv struct ChunkPlan {
  options : ChunkOptions
  parts : Array[Bytes]
  raw_size : Int32
  size_width : Int32
  filtered : Bool
}

///|
fn ChunkPlan::entry_size(self : ChunkPlan) -> Int32 {
  if self.filtered {
    12 + self.size_width
  } else {
    8
  }
}

///|
fn ChunkPlan::total_bytes(self : ChunkPlan) -> Int32 raise H5Error {
  let mut size = checked_add(
    46,
    checked_mul(self.parts.length(), self.entry_size()),
  )
  for part in self.parts {
    size = checked_add(size, part.length())
  }
  size
}

///|
fn prepare_chunks(
  value : ArrayValue,
  options : ChunkOptions,
  limits : Limits,
) -> ChunkPlan raise H5Error {
  options.validate(value, limits)
  guard value.space is Simple(shape) else {
    raise Invalid("chunk writer dataspace", 0)
  }
  let grid = shape.mapi((i, n) => {
    n / options.shape[i] + (if n % options.shape[i] == 0 { 0 } else { 1 })
  })
  let width = value.dtype.width()
  let mut elements = 1
  let mut count = 1
  for i, n in options.shape {
    elements = checked_mul(elements, n)
    count = checked_mul(count, grid[i])
  }
  let raw_size = checked_mul(elements, width)
  let parts : Array[Bytes] = []
  let mut retained = 0
  for chunk = 0; chunk < count; chunk = chunk + 1 {
    let origin = Array::make(shape.length(), 0)
    let mut remaining = chunk
    for j = shape.length() - 1; j >= 0; j = j - 1 {
      origin[j] = remaining % grid[j] * options.shape[j]
      remaining /= grid[j]
    }
    let raw = Array::make(raw_size, b'\x00')
    for cell = 0; cell < elements; cell = cell + 1 {
      let mut rest = cell
      let mut source = 0
      let mut stride = 1
      let mut inside = true
      for j = shape.length() - 1; j >= 0; j = j - 1 {
        let coordinate = origin[j] + rest % options.shape[j]
        rest /= options.shape[j]
        if coordinate >= shape[j] {
          inside = false
        } else {
          source += coordinate * stride
        }
        stride = checked_mul(stride, shape[j])
      }
      if inside {
        for b = 0; b < width; b = b + 1 {
          raw[cell * width + b] = value.raw[source * width + b]
        }
      }
    }
    let part = encode_filters(Bytes::from_array(raw), options, width)
    retained = checked_add(retained, part.length())
    if retained > limits.max_file_bytes {
      raise Limit("encoded chunk storage")
    }
    parts.push(part)
  }
  // HDF5 filtered fixed-array chunk size field has one extra byte beyond
  // the byte width required for the unfiltered size (compression can expand).
  let size_width = type_offset_width(raw_size) + 1
  let plan : ChunkPlan = {
    options,
    parts,
    raw_size,
    size_width,
    filtered: !options.pipeline(width).is_empty(),
  }
  if plan.total_bytes() > limits.max_file_bytes {
    raise Limit("chunk index/output bytes")
  }
  let metadata = checked_add(46, checked_mul(count, plan.entry_size()))
  if metadata > limits.max_metadata_bytes {
    raise Limit("chunk write metadata")
  }
  plan
}

///|
fn ChunkPlan::encode(self : ChunkPlan, address : Int32) -> Bytes raise H5Error {
  let client = if self.filtered { 1 } else { 0 }
  let h = buffer()
  h.bytes(b"FAHD")
  h.u8(0)
  h.u8(client)
  h.u8(self.entry_size())
  h.u8(30)
  h.uint(self.parts.length().to_uint64(), 8)
  h.uint((address + 28).to_uint64(), 8)
  h.uint(metadata_checksum(h.finish()).to_uint64(), 4)
  let data = buffer()
  data.bytes(b"FADB")
  data.u8(0)
  data.u8(client)
  data.uint(address.to_uint64(), 8)
  let mut at = checked_add(
    address,
    checked_add(46, checked_mul(self.parts.length(), self.entry_size())),
  )
  for part in self.parts {
    if !self.filtered && part.length() != self.raw_size {
      raise Invalid("unfiltered chunk size", address)
    }
    data.uint(at.to_uint64(), 8)
    if self.filtered {
      data.uint(part.length().to_uint64(), self.size_width)
      data.uint(0UL, 4)
    }
    at = checked_add(at, part.length())
  }
  data.uint(metadata_checksum(data.finish()).to_uint64(), 4)
  let b = buffer()
  b.bytes(h.finish())
  b.bytes(data.finish())
  for part in self.parts {
    b.bytes(part)
  }
  b.finish()
}
