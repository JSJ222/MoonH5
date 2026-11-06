///|
fn main raise {
  let samples = @h5.ArrayValue::from_unsigned(Simple([2, 3]), [
    1UL, 2UL, 18446744073709551615UL, 4UL, 5UL, 6UL,
  ])
  let reordered = samples.take_axis(1, [2, 0, 2])
  let flattened = reordered.reshape(Simple([6]))
  assert_eq(flattened.unsigned_at(0), 18446744073709551615UL)
  assert_eq(flattened.unsigned_at(2), 18446744073709551615UL)
  let doc = @h5.Document::new()
  doc.add_dataset("/selected-sensors", flattened)
  assert_eq(
    @h5.H5File::open(doc.encode()).read("/selected-sensors").bytes(),
    flattened.bytes(),
  )
  println(
    "Ordered sensor-axis gather and reshape preserve UInt64 samples through HDF5 IO",
  )
}
