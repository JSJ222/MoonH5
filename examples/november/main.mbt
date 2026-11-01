///|
fn main raise {
  let readings = @h5.ArrayValue::from_signed(Simple([2, 3]), [
    1L, 2L, 3L, 4L, 5L, 9007199254740993L,
  ])
  let channels_first = readings.transpose([1, 0])
  assert_eq(channels_first.signed_at(5), 9007199254740993L)
  let joined = channels_first.concat_axis(channels_first, 1)
  let doc = @h5.Document::new()
  doc.add_dataset("/joined-channels", joined)
  let restored = @h5.H5File::open(doc.encode()).read("/joined-channels")
  assert_eq(restored.dataspace(), Simple([3, 4]))
  assert_eq(restored.bytes(), joined.bytes())
  println(
    "HDF5 array adapter: channel-axis permutation and batch concatenation preserve exact Int64 data",
  )
}
