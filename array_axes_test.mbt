///|
test "axis permutation and concatenation preserve exact 64-bit samples" {
  let a = @moonh5.ArrayValue::from_unsigned(Simple([2, 3]), [
    0UL, 1UL, 18446744073709551615UL, 3UL, 4UL, 5UL,
  ])
  let t = a.transpose([1, 0])
  assert_eq(t.dataspace(), Simple([3, 2]))
  assert_eq(t.unsigned_at(1), 3UL)
  assert_eq(t.unsigned_at(4), 18446744073709551615UL)
  assert_eq(t.transpose([1, 0]).bytes(), a.bytes())
  let joined = a.concat_axis(a, 1)
  assert_eq(joined.dataspace(), Simple([2, 6]))
  for r = 0; r < 2; r = r + 1 {
    for c = 0; c < 6; c = c + 1 {
      assert_eq(joined.unsigned_at(r * 6 + c), a.unsigned_at(r * 3 + c % 3))
    }
  }
  let doc = @moonh5.Document::new()
  doc.add_dataset("/channels-first", t)
  assert_eq(
    @moonh5.H5File::open(doc.encode()).read("/channels-first").bytes(),
    t.bytes(),
  )
}

///|
test "axis operations reject invalid permutations, types, extents and budgets" {
  let a = @moonh5.ArrayValue::from_signed(Simple([2, 2]), [1L, 2L, 3L, 4L])
  assert_true(
    try {
      ignore(a.transpose([0, 0]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(a.transpose([-1, 0]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(a.concat_axis(a, 2))
      false
    } catch {
      _ => true
    },
  )
  let wrong = @moonh5.ArrayValue::from_unsigned(Simple([2, 2]), [
    1UL, 2UL, 3UL, 4UL,
  ])
  assert_true(
    try {
      ignore(a.concat_axis(wrong, 0))
      false
    } catch {
      _ => true
    },
  )
  let empty = @moonh5.ArrayValue::from_signed(Simple([0, 2]), [])
  assert_eq(empty.transpose([1, 0]).dataspace(), Simple([2, 0]))
  assert_eq(empty.concat_axis(a, 0).bytes(), a.bytes())
  let limits = { ..@moonh5.Limits::default(), max_elements: 4, }
  assert_true(
    try {
      ignore(a.concat_axis(a, 0, limits~))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "three-axis permutations match an independent coordinate oracle" {
  let a = @moonh5.ArrayValue::from_signed(
    Simple([2, 3, 4]),
    Array::makei(24, i => i.to_int64()),
  )
  for axes in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
    let result = a.transpose(axes)
    let shape = [2, 3, 4]
    let dims = axes.map(i => shape[i])
    let mut flat = 0
    for x = 0; x < dims[0]; x = x + 1 {
      for y = 0; y < dims[1]; y = y + 1 {
        for z = 0; z < dims[2]; z = z + 1 {
          let coords = [0, 0, 0]
          coords[axes[0]] = x
          coords[axes[1]] = y
          coords[axes[2]] = z
          assert_eq(
            result.signed_at(flat),
            (coords[0] * 12 + coords[1] * 4 + coords[2]).to_int64(),
          )
          flat += 1
        }
      }
    }
  }
}
