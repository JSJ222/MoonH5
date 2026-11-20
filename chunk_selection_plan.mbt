///|
/// Enumerate stored chunks that intersect the selection without decoding them.
pub fn H5File::plan_chunks(
  self : H5File,
  path : String,
  selection : Selection,
) -> Array[ChunkInfo] raise H5Error {
  let info = self.dataset_info(path)
  if info.dataspace != selection.source {
    raise Invalid("selection source extent differs", 0)
  }
  let dims = match info.storage {
    Chunked(_, dims)
    | FixedArray(_, dims, _)
    | SingleChunk(_, dims, _, _)
    | ImplicitChunks(_, dims) => dims
    _ => raise Invalid("not chunked", 0)
  }
  self
  .chunk_index(info)
  .filter(chunk => {
    for axis, slot in selection.axes {
      let low = chunk.origin[axis].to_int64()
      let high = low + dims[axis].to_int64() - 1L
      let start = slot.start.to_int64()
      let block = slot.block.to_int64()
      let stride = slot.stride.to_int64()
      // First selected block whose right endpoint can reach the chunk.
      let delta = low - start - block + 1L
      let i = if delta <= 0L { 0L } else { (delta + stride - 1L) / stride }
      if i >= slot.count.to_int64() || start + i * stride > high {
        return false
      }
    }
    true
  })
}
