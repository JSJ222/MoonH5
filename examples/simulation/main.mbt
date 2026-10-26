///| Extract a spatial transect from a simulation cube [time, latitude, longitude].
fn main raise {
  let shape : @h5.Dataspace = Simple([4, 3, 5])
  let values = @h5.ArrayValue::from_floats(shape, Array::makei(60, i => i.to_double() * 0.25))
  let doc = @h5.Document::new()
  doc.add_dataset("/pressure", values.with_byte_order(Big))
  doc.set_attribute("/pressure", "axes", @h5.ArrayValue::from_strings(Simple([3]), ["time", "latitude", "longitude"], 12))
  let file = @h5.H5File::open(doc.encode())
  let selection = @h5.Selection::new(shape, [
    { start: 1, stride: 2, count: 2, block: 1 },
    { start: 1, stride: 1, count: 1, block: 1 },
    { start: 0, stride: 1, count: 5, block: 1 },
  ])
  let selected = file.read_selection("/pressure", selection)
  assert_eq(selected.dataspace(), Simple([2, 1, 5]))
  assert_eq(selected.float_at(0), 5.0)
  assert_eq(selected.float_at(9), 13.5)
  let spans = selection.spans(values.datatype())
  assert_eq(spans.length(), 2)
  assert_eq(file.attributes(path="/pressure")[0].value.string_at(2), "longitude")
  println("simulation: 3D transect verified using two contiguous byte spans")
}
