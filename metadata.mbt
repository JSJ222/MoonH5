///|
pub enum Storage {
  Compact(Bytes)
  Contiguous(Int32?, Int32)
  Chunked(Int32?, Array[Int32])
} derive(Debug, Eq)

///|
pub extend Storage with @debug.Debug::{to_repr}

///|
pub extend Storage with Eq::{equal, not_equal}

///|
pub(all) struct DatasetInfo {
  datatype : DataType
  dataspace : Dataspace
  storage : Storage
  fill : Bytes
} derive(Debug)

///|
pub extend DatasetInfo with @debug.Debug::{to_repr}

///|
fn decode_layout(
  m : Message,
  sb : Superblock,
  limits : Limits,
) -> Storage raise H5Error {
  let c = cursor(m.bytes, 0, m.bytes.length())
  let version = c.u8()
  if version != 3 && version != 4 {
    raise Unsupported("data layout version", m.at)
  }
  match c.u8() {
    0 => {
      let n = c.index(2)
      Compact(c.bytes(n))
    }
    1 => {
      let address = c.address(sb.offset_width, sb.base)
      let size = c.index(sb.size_width)
      if size > limits.max_file_bytes {
        raise Limit("contiguous dataset size")
      }
      Contiguous(address, size)
    }
    2 if version == 3 => {
      let rank = c.u8()
      if rank < 2 || rank - 1 > limits.max_rank {
        raise Limit("chunk rank")
      }
      let root = c.address(sb.offset_width, sb.base)
      let dims : Array[Int32] = []
      for i = 0; i < rank; i = i + 1 {
        dims.push(c.index(4))
      }
      Chunked(root, dims)
    }
    2 => raise Unsupported("modern chunk indexes", m.at)
    _ => raise Unsupported("virtual or unknown storage", m.at)
  }
}

///|
fn decode_fill(m : Message, width : Int32) -> Bytes raise H5Error {
  let c = cursor(m.bytes, 0, m.bytes.length())
  let version = c.u8()
  let defined = match version {
    1 | 2 => {
      c.skip(2)
      c.u8() != 0
    }
    3 => {
      let flags = c.u8()
      if (flags & 0xc0) != 0 || (flags & 0x30) == 0x30 {
        raise Invalid("fill flags", m.at)
      }
      if (flags & 16) != 0 {
        raise Unsupported("undefined fill value", m.at)
      }
      (flags & 32) != 0
    }
    _ => raise Unsupported("fill message version", m.at)
  }
  if !defined {
    raise Unsupported("undefined fill value", m.at)
  }
  let size = c.index(4)
  if size == 0 {
    return Bytes::from_array(Array::make(width, 0))
  }
  if size != width {
    raise Invalid("fill size differs from datatype", m.at)
  }
  c.bytes(size)
}

///|
pub fn H5File::dataset_info(
  self : H5File,
  path : String,
) -> DatasetInfo raise H5Error {
  let messages = self.messages(self.resolve(path))
  let mut dtype : DataType? = None
  let mut space : Dataspace? = None
  let mut storage : Storage? = None
  let mut fill_message : Message? = None
  for m in messages {
    let c = cursor(m.bytes, 0, m.bytes.length())
    match m.kind {
      1 => {
        if space != None {
          raise Invalid("duplicate dataspace", m.at)
        }
        space = Some(decode_space(c, self.sb.size_width, self.limits))
      }
      3 => {
        if dtype != None {
          raise Invalid("duplicate datatype", m.at)
        }
        dtype = Some(decode_type(c))
      }
      8 => {
        if storage != None {
          raise Invalid("duplicate data layout", m.at)
        }
        storage = Some(decode_layout(m, self.sb, self.limits))
      }
      5 => {
        if fill_message is Some(_) {
          raise Invalid("duplicate fill value", m.at)
        }
        fill_message = Some(m)
      }
      7 => raise Unsupported("external dataset files", m.at)
      _ =>
        if (m.flags & 128) != 0 &&
          m.kind != 12 &&
          m.kind != 11 &&
          m.kind != 21 &&
          m.kind != 22 {
          raise Unsupported("mandatory dataset message", m.at)
        }
    }
  }
  guard dtype is Some(datatype) else { raise Invalid("missing datatype", 0) }
  guard space is Some(dataspace) else { raise Invalid("missing dataspace", 0) }
  guard storage is Some(storage) else {
    raise Invalid("missing data layout", 0)
  }
  let width = datatype.width()
  let size = checked_mul(dataspace.elements(limits=self.limits), width)
  if size > self.limits.max_file_bytes {
    raise Limit("dataset bytes")
  }
  match storage {
    Compact(data) =>
      if data.length() != size {
        raise Invalid("compact size mismatch", 0)
      }
    Contiguous(_, n) =>
      if n != size {
        raise Invalid("contiguous size mismatch", 0)
      }
    Chunked(_, dims) => {
      guard dataspace is Simple(shape) else {
        raise Invalid("chunked non-simple dataspace", 0)
      }
      if dims.length() != shape.length() + 1 || dims.last() != Some(width) {
        raise Invalid("chunk dimensions", 0)
      }
      let mut total = 1
      for dim in dims {
        if dim <= 0 {
          raise Invalid("zero chunk dimension", 0)
        }
        total = checked_mul(total, dim)
      }
      if total > self.limits.max_file_bytes {
        raise Limit("chunk bytes")
      }
    }
  }
  let fill = match fill_message {
    Some(m) => decode_fill(m, width)
    None => Bytes::from_array(Array::make(width, 0))
  }
  { datatype, dataspace, storage, fill, }
}
