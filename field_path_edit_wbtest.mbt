///|
test "nested edits preserve surrounding bytes and the original value" {
  let old = nested_records()
  let replacement = ArrayValue::new(
    Unsigned(2, Big),
    Simple([2]),
    b"\x13\x24\x24\x35",
  )
  let next = old.with_field_path(["outer", "reading"], replacement)
  assert_eq(next.bytes(), b"\xff\xff\x13\x24\xff\xff\xee\xee\x24\x35\xee\xee")
  assert_eq(old.field_path(["outer", "reading"]).unsigned_at(0), 258UL)
}
