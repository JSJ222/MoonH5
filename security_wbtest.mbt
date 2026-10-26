///| White-box corruption cases exercise internal bounded readers as well as public APIs.
fn sample_document() -> Bytes raise H5Error {
  let doc = Document::new()
  doc.add_group("/g")
  doc.add_dataset("/g/a", ArrayValue::from_signed(Simple([2, 3]), [0L, 1L, 2L, 3L, 4L, 5L]))
  doc.set_attribute("/g/a", "unit", ArrayValue::from_strings(Scalar, ["K"], 1))
  doc.encode()
}

///|
test "every prefix of a small HDF5 file fails before returning partial data" {
  let bytes = sample_document()
  for n = 0; n < bytes.length(); n = n + 1 {
    let rejected = try {
      let file = H5File::open(bytes[:n].to_owned())
      ignore(file.read("/g/a"))
      false
    } catch { _ => true }
    assert_true(rejected)
  }
}

///|
test "every single-byte mutation of the superblock is rejected" {
  let bytes = sample_document()
  for at = 0; at < 48; at = at + 1 {
    let mutated = bytes.to_array()
    mutated[at] = (mutated[at].to_int() ^ 1).to_byte()
    assert_true(try { ignore(H5File::open(Bytes::from_array(mutated))); false } catch { _ => true })
  }
}

///|
test "metadata checksum corruption never returns plausible replacement data" {
  let bytes = sample_document()
  let file = H5File::open(bytes)
  let at = file.object_address("/g/a")
  let bad = bytes.to_array()
  bad[at + 15] = (bad[at + 15].to_int() ^ 128).to_byte()
  let f = H5File::open(Bytes::from_array(bad))
  assert_true(try { ignore(f.read("/g/a")); false } catch { _ => true })
}

///|
test "caller resource ceilings apply independently to files extents and traversal" {
  let bytes = sample_document()
  let small_file = { ..Limits::default(), max_file_bytes: bytes.length() - 1 }
  assert_true(try { ignore(H5File::open(bytes, limits=small_file)); false } catch { _ => true })
  let small_elements = { ..Limits::default(), max_elements: 5 }
  let file = H5File::open(bytes, limits=small_elements)
  assert_true(try { ignore(file.read("/g/a")); false } catch { _ => true })
  let small_metadata = { ..Limits::default(), max_metadata_bytes: 4 }
  assert_true(try { ignore(H5File::open(bytes, limits=small_metadata)); false } catch { _ => true })
  let invalid = { ..Limits::default(), max_depth: 0 }
  assert_true(try { ignore(H5File::open(bytes, limits=invalid)); false } catch { _ => true })
}

///|
test "required unknown messages and shared message payloads fail closed" {
  let unknown : Message = { kind: 127, flags: 128, bytes: b"", at: 100 }
  let sb : Superblock = { version: 2, offset_width: 8, size_width: 8, base: 0, root: 0, eof: 0 }
  assert_true(try { ignore(group_links(b"", sb, [unknown], Limits::default())); false } catch { _ => true })
  let shared : Message = { kind: 3, flags: 2, bytes: b"abc", at: 0 }
  let header = encode_header([shared], Limits::default())
  let sb = { ..sb, eof: header.length() }
  assert_true(try { ignore(read_messages(header, sb, 0, Limits::default())); false } catch { _ => true })
}

///|
test "undefined fill is not silently converted to zero" {
  assert_true(try { ignore(decode_fill(message(5, b"\x02\x02\x02\x00"), 8)); false } catch { _ => true })
}

///|
test "declared EOF prevents parsing metadata from a trailing transport suffix" {
  let doc = Document::new()
  doc.add_group("/g")
  let bytes = doc.encode()
  let root = H5File::open(bytes).sb.root
  let raw = bytes.to_array()
  let block = write_superblock(root, root + 1)
  for i = 0; i < 48; i = i + 1 { raw[i] = block[i] }
  assert_true(try { ignore(H5File::open(Bytes::from_array(raw))); false } catch { _ => true })
}
