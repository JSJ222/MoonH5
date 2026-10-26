///| Store fixed-shape model parameters; update a submatrix without mutating input.
fn main raise {
  let weights = @h5.ArrayValue::from_floats(Simple([3, 4]), Array::make(12, 0.0))
  let selection = @h5.Selection::new(weights.dataspace(), [
    { start: 1, stride: 1, count: 2, block: 1 },
    { start: 0, stride: 2, count: 2, block: 1 },
  ])
  let replacement = @h5.ArrayValue::from_floats(Simple([2, 2]), [0.25, -0.5, 0.75, 1.0])
  let updated = weights.with_selection(selection, replacement)
  assert_eq(weights.float_at(4), 0.0)
  assert_eq(updated.float_at(4), 0.25)
  let doc = @h5.Document::new()
  doc.add_group("/parameters")
  doc.add_dataset("/parameters/weights", updated)
  doc.set_attribute("/parameters/weights", "layout", @h5.ArrayValue::from_strings(Scalar, ["row-major"], 12))
  doc.add_hard_link("/weights", "/parameters/weights")
  let source = @h5.H5File::open(doc.encode())
  let portable = @h5.H5File::open(source.to_document().encode())
  assert_eq(portable.read_selection("/weights", selection).bytes(), replacement.bytes())
  assert_eq(portable.object_address("/weights"), portable.object_address("/parameters/weights"))
  println("training: parameter update, portable HDF5 serialization, and aliases verified")
}
