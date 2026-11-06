///|
/// A regular non-overlapping block selection along one axis.
pub(all) struct Axis {
  start : Int32
  stride : Int32
  count : Int32
  block : Int32
} derive(Debug, Eq)

///|
pub extend Axis with @debug.Debug::{to_repr}

///|
pub extend Axis with Eq::{equal, not_equal}

///|
pub struct Selection {
  source : Dataspace
  result : Dataspace
  axes : Array[Axis]
  limits : Limits
}

///|
pub fn Selection::new(
  space : Dataspace,
  axes : Array[Axis],
  limits~ : Limits = Limits::default(),
) -> Selection raise H5Error {
  ignore(space.elements(limits~))
  let result = match space {
    Scalar | Null => {
      if axes.length() != 0 {
        raise Invalid("scalar/null selection has axes", 0)
      }
      space
    }
    Simple(shape) => {
      if axes.length() != shape.length() {
        raise Invalid("selection rank differs", 0)
      }
      let dims : Array[Int32] = []
      for i = 0; i < axes.length(); i = i + 1 {
        let a = axes[i]
        if a.start < 0 || a.stride <= 0 || a.count < 0 || a.block <= 0 {
          raise Invalid("invalid hyperslab axis", i)
        }
        if a.count > 1 && a.stride < a.block {
          raise Unsupported("overlapping hyperslab blocks", i)
        }
        if a.count == 0 {
          if a.start > shape[i] {
            raise Invalid("empty selection begins outside extent", i)
          }
        } else {
          let end = checked_add(
            a.start,
            checked_add(checked_mul(a.count - 1, a.stride), a.block),
          )
          if end > shape[i] {
            raise Invalid("selection exceeds extent", i)
          }
        }
        dims.push(checked_mul(a.count, a.block))
      }
      Simple(dims)
    }
  }
  ignore(result.elements(limits~))
  { source: space.copy(), result, axes: axes.copy(), limits, }
}

///|
pub fn Selection::all(
  space : Dataspace,
  limits~ : Limits = Limits::default(),
) -> Selection raise H5Error {
  let axes = match space {
    Simple(shape) =>
      shape.map(n => { start: 0, stride: 1, count: n, block: 1, })
    _ => []
  }
  Selection::new(space, axes, limits~)
}

///|
pub fn Selection::dataspace(self : Selection) -> Dataspace {
  self.result.copy()
}

///|
fn Selection::source_index(
  self : Selection,
  output : Int32,
) -> Int32 raise H5Error {
  let n = self.result.elements(limits=self.limits)
  if output < 0 || output >= n {
    raise Invalid("selection output index", output)
  }
  match (self.source, self.result) {
    (Scalar, Scalar) => 0
    (Simple(source), Simple(result)) => {
      let mut left = output
      let mut multiplier = 1
      let mut index = 0
      for i = source.length() - 1; i >= 0; i = i - 1 {
        let coordinate = left % result[i]
        left /= result[i]
        let axis = self.axes[i]
        let original = axis.start +
          coordinate / axis.block * axis.stride +
          coordinate % axis.block
        index = checked_add(index, checked_mul(original, multiplier))
        multiplier = checked_mul(multiplier, source[i])
      }
      index
    }
    _ => raise Invalid("no source index in null/empty selection", output)
  }
}

///|
pub(all) struct ReadSpan {
  source_byte : Int32
  output_byte : Int32
  length : Int32
} derive(Debug, Eq)

///|
pub extend ReadSpan with @debug.Debug::{to_repr}

///|
pub extend ReadSpan with Eq::{equal, not_equal}

///|
/// Coalesces consecutive elements. Plans are relative to dataset raw bytes.
pub fn Selection::spans(
  self : Selection,
  datatype : DataType,
) -> Array[ReadSpan] raise H5Error {
  let width = datatype.width()
  let count = self.result.elements(limits=self.limits)
  if checked_mul(count, width) > self.limits.max_file_bytes {
    raise Limit("selection bytes")
  }
  let spans : Array[ReadSpan] = []
  for i = 0; i < count; i = i + 1 {
    let offset = checked_mul(self.source_index(i), width)
    if spans.last() is Some(last) && last.source_byte + last.length == offset {
      spans[spans.length() - 1] = {
        ..last,
        length: checked_add(last.length, width),
      }
    } else {
      if spans.length() >= self.limits.max_objects {
        raise Limit("selection span count")
      }
      spans.push({
        source_byte: offset,
        output_byte: checked_mul(i, width),
        length: width,
      })
    }
  }
  spans
}

///|
pub fn ArrayValue::select(
  self : ArrayValue,
  selection : Selection,
) -> ArrayValue raise H5Error {
  if self.space != selection.source {
    raise Invalid("selection source extent differs", 0)
  }
  let b = buffer()
  for span in selection.spans(self.dtype) {
    b.bytes(bytes_at(self.raw, span.source_byte, span.length))
  }
  ArrayValue::new(
    self.dtype,
    selection.result,
    b.finish(),
    limits=selection.limits,
  )
}

///|
pub fn H5File::read_selection(
  self : H5File,
  path : String,
  selection : Selection,
) -> ArrayValue raise H5Error {
  let info = self.dataset_info(path)
  if info.dataspace != selection.source {
    raise Invalid("selection source extent differs", 0)
  }
  let count = selection.result.elements(limits=self.limits)
  if checked_mul(count, info.datatype.width()) > self.limits.max_file_bytes {
    raise Limit("selected dataset bytes")
  }
  let b = buffer()
  match info.storage {
    Compact(raw) =>
      for span in selection.spans(info.datatype) {
        b.bytes(bytes_at(raw, span.source_byte, span.length))
      }
    Contiguous(Some(address), _) =>
      for span in selection.spans(info.datatype) {
        b.bytes(self.range(checked_add(address, span.source_byte), span.length))
      }
    Contiguous(None, _) => b.bytes(repeated_fill(info.fill, count, self.limits))
    Chunked(_, _)
    | FixedArray(_, _, _)
    | SingleChunk(_, _, _, _)
    | ImplicitChunks(_, _) =>
      return self.read_chunked_selection(path, info, selection)
  }
  ArrayValue::new(
    info.datatype,
    selection.result,
    b.finish(),
    limits=self.limits,
  )
}

///|
test "regular block hyperslab preserves row-major order" {
  let source = ArrayValue::from_signed(
    Simple([4, 6]),
    Array::makei(24, i => i.to_int64()),
  )
  let selection = Selection::new(source.space, [
    { start: 1, stride: 2, count: 2, block: 1, },
    { start: 0, stride: 3, count: 2, block: 2, },
  ])
  let result = source.select(selection)
  assert_eq(result.dataspace(), Simple([2, 4]))
  let ints = Array::makei(8, i => result.signed_at(i))
  assert_eq(ints, [6L, 7L, 9L, 10L, 18L, 19L, 21L, 22L])
  assert_eq(selection.spans(source.dtype).length(), 4)
  let doc = Document::new()
  doc.add_dataset("/array", source)
  assert_eq(
    H5File::open(doc.encode()).read_selection("/array", selection).bytes(),
    result.bytes(),
  )
}

///|
test "hyperslab boundary empty overflow and overlap validation" {
  let empty = Selection::new(Simple([3]), [
    { start: 3, stride: 1, count: 0, block: 1, },
  ])
  assert_eq(empty.dataspace(), Simple([0]))
  assert_eq(empty.spans(Signed(8, Little)), [])
  assert_true(
    try {
      ignore(
        Selection::new(Simple([5]), [
          { start: 0, stride: 1, count: 2, block: 2, },
        ]),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        Selection::new(Simple([5]), [
          { start: 4, stride: 1, count: 2, block: 1, },
        ]),
      )
      false
    } catch {
      _ => true
    },
  )
}
