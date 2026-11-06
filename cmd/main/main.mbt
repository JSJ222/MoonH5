///|
fn type_name(dtype : @h5.DataType) -> String {
  match dtype {
    Signed(n, _) => "i\{n}"
    Unsigned(n, _) => "u\{n}"
    Float(n, _) => "f\{n}"
    FixedString(n, _, _) => "S\{n}"
    Compound(_, _) => "compound"
    ArrayType(_, _) => "array"
    EnumType(_, _) => "enum"
  }
}

///|
fn array_json(value : @h5.ArrayValue) -> Json raise {
  let shape : Json = match value.dataspace() {
    Scalar => Json::array([])
    Null => Json::null()
    Simple(dims) => Json::array(dims.map(n => Json::number(n.to_double())))
  }
  let values : Array[Json] = []
  for i = 0; i < value.length(); i = i + 1 {
    values.push(
      match value.datatype() {
        Signed(_, _) => Json::string(value.signed_at(i).to_string())
        Unsigned(_, _) => Json::string(value.unsigned_at(i).to_string())
        Float(_, _) => {
          let n = value.float_at(i)
          if n.is_nan() {
            Json::string("NaN")
          } else if n.is_inf() {
            Json::string(if n < 0 { "-Infinity" } else { "Infinity" })
          } else if n == 0.0 &&
            n.reinterpret_as_uint64() == 0x8000000000000000UL {
            Json::string("-0")
          } else {
            Json::number(n)
          }
        }
        FixedString(_, _, _) => Json::string(value.string_at(i))
        Compound(_, _) | ArrayType(_, _) | EnumType(_, _) =>
          Json::array(
            value
            .element(i)
            .bytes()
            .to_array()
            .map(b => Json::number(b.to_double())),
          )
      },
    )
  }
  Json::object({
    "type": Json::string(type_name(value.datatype())),
    "shape": shape,
    "values": Json::array(values),
  })
}

///|
async fn run() -> Unit {
  let args = @env.args()
  if args.length() == 4 &&
    (args[1] == "repack" || args[1] == "repack-compressed") {
    let limits = @h5.Limits::default()
    if @fs.file_size(args[2][:]) > limits.max_file_bytes.to_int64() {
      raise Failure("CLI input byte limit")
    }
    let file = @h5.H5File::open(@fs.read_file(args[2][:]).binary())
    let doc = file.to_document()
    if args[1] == "repack-compressed" {
      for entry in file.walk() {
        if entry.dataset &&
          file.dataset_info(entry.path).dataspace is Simple(shape) &&
          !shape.contains(0) {
          doc.set_chunking(
            entry.path,
            Some(
              @h5.ChunkOptions::new(
                shape.map(n => if n < 16 { n } else { 16 }),
                gzip=Some(6),
                shuffle=true,
                fletcher32=true,
              ),
            ),
          )
        }
      }
    }
    @fs.write_file(args[3][:], doc.encode(), create_mode=CreateNew)
    println("created semantically repacked HDF5 file")
    return
  }
  if args.length() != 3 ||
    !["read", "write-demo", "write-format"].contains(args[1]) {
    raise Failure(
      "usage: moonh5 read FILE.h5 | write-demo NEW.h5 | repack INPUT.h5 NEW.h5",
    )
  }
  if args[1] == "write-format" {
    let doc = @h5.Document::new()
    let kind : @h5.DataType = Compound(24, [
      { name: "id", offset: 0, datatype: Unsigned(8, Big), },
      { name: "pair", offset: 8, datatype: ArrayType([2], Float(4, Little)), },
      {
        name: "state",
        offset: 16,
        datatype: EnumType(Unsigned(1, Little), [
          ("OFF", b"\x00"),
          ("ON", b"\x01"),
        ]),
      },
    ])
    let raw : Array[Byte] = []
    for i = 0; i < 15; i = i + 1 {
      let id = 0xffffffffffffffffUL - i.to_uint64()
      for j = 7; j >= 0; j = j - 1 {
        raw.push((id >> (8 * j)).to_byte())
      }
      for n in [i.to_double(), -i.to_double()] {
        let bits = Float::from_double(n).reinterpret_as_uint()
        for j = 0; j < 4; j = j + 1 {
          raw.push((bits >> (8 * j)).to_byte())
        }
      }
      raw.push((i % 2).to_byte())
      for j = 0; j < 7; j = j + 1 {
        raw.push(b'\x00')
      }
    }
    let value = @h5.ArrayValue::new(
      kind,
      Simple([3, 5]),
      Bytes::from_array(raw),
    )
    doc.add_dataset(
      "/records",
      value,
      chunked=Some(
        @h5.ChunkOptions::new(
          [2, 3],
          gzip=Some(6),
          shuffle=true,
          fletcher32=true,
        ),
      ),
    )
    doc.set_attribute("/records", "sample", value.element(0))
    doc.add_dataset(
      "/dense",
      @h5.ArrayValue::from_signed(Simple([32, 32]), Array::make(1024, 7L)),
      chunked=Some(@h5.ChunkOptions::new([8, 8], gzip=Some(6), shuffle=true)),
    )
    doc.add_dataset(
      "/many_chunks",
      @h5.ArrayValue::from_signed(
        Simple([33, 35]),
        Array::makei(1155, i => i.to_int64()),
      ),
      chunked=Some(@h5.ChunkOptions::new([1, 1], gzip=Some(0))),
    )
    doc.add_group("/levels")
    for level in [0, 1, 9] {
      doc.add_dataset(
        "/levels/gzip" + level.to_string(),
        @h5.ArrayValue::from_unsigned(Simple([7]), [
          1UL, 2UL, 3UL, 4UL, 5UL, 6UL, 0xffffffffffffffffUL,
        ]),
        chunked=Some(
          @h5.ChunkOptions::new([3], gzip=Some(level), fletcher32=true),
        ),
      )
    }
    @fs.write_file(args[2][:], doc.encode(), create_mode=CreateNew)
    println("created structured and compressed HDF5 file")
  } else if args[1] == "write-demo" {
    let doc = @h5.Document::new()
    doc.add_group("/experiment")
    doc.add_dataset(
      "/experiment/samples",
      @h5.ArrayValue::from_floats(Simple([2, 3]), [0.5, 1.5, 2.5, 3.5, 4.5, 5.5]),
    )
    doc.add_dataset(
      "/counter",
      @h5.ArrayValue::from_signed(Scalar, [-9223372036854775808L]),
      compact=true,
    )
    doc.add_dataset(
      "/labels",
      @h5.ArrayValue::from_strings(Simple([2]), ["alpha", "温度"], 8),
    )
    doc.add_dataset(
      "/null",
      @h5.ArrayValue::new(Unsigned(1, Little), Null, b""),
    )
    doc.add_dataset(
      "/empty",
      @h5.ArrayValue::new(Unsigned(1, Little), Simple([0, 2]), b""),
    )
    doc.add_hard_link("/alias", "/experiment/samples")
    doc.set_attribute(
      "/experiment",
      "unit",
      @h5.ArrayValue::from_strings(Scalar, ["K"], 4),
    )
    doc.set_attribute(
      "/counter",
      "revision",
      @h5.ArrayValue::from_signed(Scalar, [7L]),
    )
    @fs.write_file(args[2][:], doc.encode(), create_mode=CreateNew)
    println("created HDF5 demo")
  } else {
    let limits = @h5.Limits::default()
    if @fs.file_size(args[2][:]) > limits.max_file_bytes.to_int64() {
      raise Failure("CLI input byte limit")
    }
    let file = @h5.H5File::open(@fs.read_file(args[2][:]).binary())
    let entries : Array[Json] = []
    for entry in file.walk() {
      let attrs = file
        .attributes(path=entry.path)
        .map(a => {
          Json::object({
            "name": Json::string(a.name),
            "value": array_json(a.value),
          })
        })
      let object : Map[String, Json] = {
        "path": Json::string(entry.path),
        "attributes": Json::array(attrs),
      }
      if entry.dataset {
        object["data"] = array_json(file.read(entry.path))
      }
      entries.push(Json::object(object))
    }
    println(Json::array(entries).stringify())
  }
}

///|
async fn main {
  run() catch {
    @h5.H5Error::Invalid(message, offset) =>
      raise Failure("invalid HDF5 at byte \{offset}: \{message}")
    @h5.H5Error::Unsupported(message, offset) =>
      raise Failure("unsupported HDF5 at byte \{offset}: \{message}")
    @h5.H5Error::Limit(message) =>
      raise Failure("HDF5 resource limit: \{message}")
    @h5.H5Error::NotFound(path) =>
      raise Failure("HDF5 object not found: \{path}")
    error => raise error
  }
}
