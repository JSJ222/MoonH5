///|
/// Read a nested field from a selection. Contiguous and compact inputs copy
/// only the requested field bytes. Chunked inputs decode the selected records.
pub fn H5File::read_field_selection(
  self : H5File,
  path : String,
  selection : Selection,
  field : Array[String],
) -> ArrayValue raise H5Error {
  let info = self.dataset_info(path)
  if info.dataspace != selection.source {
    raise Invalid("selection source extent differs", 0)
  }
  let (dtype, offset) = compound_leaf(info.datatype, field)
  let count = selection.result.elements(limits=self.limits)
  let width = dtype.width()
  if checked_mul(count, width) > self.limits.max_file_bytes {
    raise Limit("selected field bytes")
  }
  let record = info.datatype.width()
  let out = buffer()
  match info.storage {
    Compact(raw) =>
      for i = 0; i < count; i = i + 1 {
        let pos = checked_add(
          checked_mul(selection.source_index(i), record),
          offset,
        )
        out.bytes(bytes_at(raw, pos, width))
      }
    Contiguous(Some(address), _) =>
      for i = 0; i < count; i = i + 1 {
        let pos = checked_add(
          checked_mul(selection.source_index(i), record),
          offset,
        )
        out.bytes(self.range(checked_add(address, pos), width))
      }
    Contiguous(None, _) =>
      out.bytes(
        repeated_fill(bytes_at(info.fill, offset, width), count, self.limits),
      )
    _ =>
      return self
        .read_selection(path, selection)
        .field_path(field, limits=self.limits)
  }
  ArrayValue::new(dtype, selection.result, out.finish(), limits=self.limits)
}
