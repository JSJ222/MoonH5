///| An instrument records [frame, sensor] data with independently typed metadata.
fn main raise {
  let doc = @h5.Document::new()
  doc.add_group("/acquisition")
  let samples = @h5.ArrayValue::from_floats(
    Simple([3, 4]),
    [20.1, 20.3, 21.0, 22.0, 20.2, 20.4, 21.2, 22.1, 20.4, 20.5, 21.3, 22.4],
  )
  doc.add_dataset("/acquisition/temperature", samples)
  doc.set_attribute("/acquisition/temperature", "units", @h5.ArrayValue::from_strings(Scalar, ["Celsius"], 8))
  doc.set_attribute("/acquisition", "revision", @h5.ArrayValue::from_unsigned(Scalar, [2UL]))
  doc.add_soft_link("/latest", "/acquisition/temperature")
  let bytes = doc.encode()
  let file = @h5.H5File::open(bytes)
  let selection = @h5.Selection::new(Simple([3, 4]), [
    { start: 0, stride: 2, count: 2, block: 1 },
    { start: 1, stride: 1, count: 2, block: 1 },
  ])
  let excerpt = file.read_selection("/latest", selection)
  assert_eq(excerpt.dataspace(), Simple([2, 2]))
  assert_eq(excerpt.float_at(0), 20.3)
  assert_eq(excerpt.float_at(3), 21.3)
  assert_eq(file.attributes(path="/acquisition")[0].value.unsigned_at(0), 2UL)
  println("instrument: four selected values and unit metadata verified; HDF5 bytes=\{bytes.length()}")
}
