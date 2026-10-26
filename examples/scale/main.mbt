///|
/// Reproducible correctness workload, not a claimed speed benchmark.
fn main raise {
  let doc = @h5.Document::new()
  for i = 0; i < 500; i = i + 1 {
    let name = "/series_\{i}"
    doc.add_group(name)
    let data = @h5.ArrayValue::from_signed(
      Simple([200]),
      Array::makei(200, j => (i * 200 + j).to_int64()),
    )
    doc.add_dataset(name + "/data", data)
  }
  let bytes = doc.encode()
  let file = @h5.H5File::open(bytes)
  assert_eq(file.walk().length(), 1001)
  let selection = @h5.Selection::new(Simple([200]), [
    { start: 150, stride: 3, count: 10, block: 1, },
  ])
  for i in [0, 17, 249, 499] {
    let value = file.read_selection("/series_\{i}/data", selection)
    assert_eq(value.signed_at(0), (i * 200 + 150).to_int64())
    assert_eq(value.signed_at(9), (i * 200 + 177).to_int64())
  }
  println(
    "scale: 1001 objects, 100000 int64 values, sampled hyperslabs verified, \{bytes.length()} file bytes",
  )
}
