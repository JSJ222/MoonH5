///|
pub(all) struct CompoundMember {
  name : String
  offset : Int32
  datatype : DataType
} derive(Debug, Eq)

///|
pub extend CompoundMember with @debug.Debug::{to_repr}

///|
pub extend CompoundMember with Eq::{equal, not_equal}

///|
fn type_name_valid(name : String) -> Unit raise H5Error {
  if name.is_empty() ||
    name.contains("\u0000") ||
    @utf8.encode(name).length() > 255 {
    raise Invalid("datatype field name", 0)
  }
}

///|
fn type_offset_width(n : Int32) -> Int32 {
  if n < 256 {
    1
  } else if n < 65536 {
    2
  } else if n < 16777216 {
    3
  } else {
    4
  }
}

///|
fn type_width(
  dtype : DataType,
  depth : Int32,
  budget : Ref[Int32],
) -> Int32 raise H5Error {
  budget.val -= 1
  if depth > 32 || budget.val < 0 {
    raise Limit("datatype recursion/nodes")
  }
  match dtype {
    Signed(n, _) | Unsigned(n, _) if n == 1 || n == 2 || n == 4 || n == 8 => n
    Float(n, _) if n == 4 || n == 8 => n
    FixedString(n, _, _) if n > 0 && n <= 65535 => n
    ArrayType(shape, base) => {
      if shape.is_empty() || shape.length() > 32 {
        raise Limit("array datatype rank")
      }
      let mut size = type_width(base, depth + 1, budget)
      for n in shape {
        if n <= 0 {
          raise Invalid("array datatype dimension", 0)
        }
        size = checked_mul(size, n)
      }
      size
    }
    Compound(n, members) => {
      if n <= 0 || members.is_empty() || members.length() > 256 {
        raise Limit("compound size/field count")
      }
      let names : Map[String, Bool] = Map([])
      let ranges : Array[(Int32, Int32)] = []
      for field in members {
        type_name_valid(field.name)
        if names.contains(field.name) {
          raise Invalid("duplicate compound field", 0)
        }
        names[field.name] = true
        let width = type_width(field.datatype, depth + 1, budget)
        if field.offset < 0 || field.offset > n || width > n - field.offset {
          raise Invalid("compound field outside record", 0)
        }
        for (a, b) in ranges {
          if field.offset < b && field.offset + width > a {
            raise Invalid("overlapping compound members", 0)
          }
        }
        ranges.push((field.offset, field.offset + width))
      }
      n
    }
    EnumType(base, entries) => {
      if !(base is Signed(_, _)) && !(base is Unsigned(_, _)) {
        raise Invalid("enum base must be integer", 0)
      }
      let width = type_width(base, depth + 1, budget)
      if entries.is_empty() || entries.length() > 256 {
        raise Limit("enum entries")
      }
      let names : Map[String, Bool] = Map([])
      let values : Array[Bytes] = []
      for (name, value) in entries {
        type_name_valid(name)
        if names.contains(name) ||
          values.contains(value) ||
          value.length() != width {
          raise Invalid("duplicate or invalid enum field", 0)
        }
        names[name] = true
        values.push(value)
      }
      width
    }
    _ => raise Unsupported("unsupported datatype width", 0)
  }
}

///|
fn DataType::detached(self : DataType) -> DataType {
  match self {
    Compound(n, members) =>
      Compound(n, members.map(m => { ..m, datatype: m.datatype.detached(), }))
    ArrayType(shape, base) => ArrayType(shape.copy(), base.detached())
    EnumType(base, entries) => EnumType(base.detached(), entries.copy())
    _ => self
  }
}

///|
fn type_member_name(c : Cursor, padded : Bool) -> String raise H5Error {
  let start = c.pos
  let b = buffer()
  let mut found = false
  for i = 0; i < 256; i = i + 1 {
    let byte = c.u8()
    if byte == 0 {
      found = true
      break
    }
    b.u8(byte)
  }
  if !found {
    raise Invalid("unterminated datatype field name", start)
  }
  if padded {
    c.skip((8 - (c.pos - start) % 8) % 8)
  }
  let name = text(b.finish(), start)
  type_name_valid(name)
  name
}

///|
/// Extract one exact record as a scalar without interpreting numeric bytes.
pub fn ArrayValue::element(
  self : ArrayValue,
  index : Int32,
) -> ArrayValue raise H5Error {
  ArrayValue::new(
    self.dtype,
    Scalar,
    bytes_at(self.raw, self.offset(index), self.dtype.width()),
  )
}

///|
/// Project a compound field while preserving its type and dataset shape.
pub fn ArrayValue::field(
  self : ArrayValue,
  name : String,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  guard self.dtype is Compound(width, members) else {
    raise Invalid("compound field projection", 0)
  }
  let selected : Ref[CompoundMember?] = Ref(None)
  for m in members {
    if m.name == name {
      selected.val = Some(m)
      break
    }
  }
  let field = match selected.val {
    Some(m) => m
    None => raise NotFound(name)
  }
  let field_width = field.datatype.width()
  let count = self.length()
  let size = checked_mul(count, field_width)
  if size > limits.max_file_bytes {
    raise Limit("compound field bytes")
  }
  let b = buffer()
  for i = 0; i < count; i = i + 1 {
    b.bytes(bytes_at(self.raw, i * width + field.offset, field_width))
  }
  ArrayValue::new(field.datatype, self.space, b.finish(), limits~)
}

///|
/// Expand fixed-array element dimensions after the dataset dimensions.
pub fn ArrayValue::expand_array(
  self : ArrayValue,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  guard self.dtype is ArrayType(shape, base) else {
    raise Invalid("not fixed-array datatype", 0)
  }
  let dims = match self.space {
    Scalar => []
    Simple(s) => s.copy()
    Null => return ArrayValue::new(base, Null, b"", limits~)
  }
  dims.append(shape)
  ArrayValue::new(base, Simple(dims), self.raw, limits~)
}

///|
pub fn ArrayValue::enum_base(
  self : ArrayValue,
  limits~ : Limits = Limits::default(),
) -> ArrayValue raise H5Error {
  guard self.dtype is EnumType(base, _) else {
    raise Invalid("not enum datatype", 0)
  }
  ArrayValue::new(base, self.space, self.raw, limits~)
}

///|
pub fn ArrayValue::enum_name_at(
  self : ArrayValue,
  index : Int32,
) -> String? raise H5Error {
  guard self.dtype is EnumType(base, entries) else {
    raise Invalid("not enum datatype", 0)
  }
  let raw = bytes_at(self.raw, self.offset(index), base.width())
  for (name, value) in entries {
    if raw == value {
      return Some(name)
    }
  }
  None
}
