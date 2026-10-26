///|
fn type_name(dtype : @h5.DataType) -> String {
  match dtype {
    Signed(n, _) => "i\{n}"
    Unsigned(n, _) => "u\{n}"
    Float(n, _) => "f\{n}"
    FixedString(n, _, _) => "S\{n}"
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
          } else {
            Json::number(n)
          }
        }
        FixedString(_, _, _) => Json::string(value.string_at(i))
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
  if args.length() == 4 && args[1] == "repack" {
    let limits = @h5.Limits::default()
    if @fs.file_size(args[2][:]) > limits.max_file_bytes.to_int64() { raise Failure("CLI input byte limit") }
    let file = @h5.H5File::open(@fs.read_file(args[2][:]).binary())
    @fs.write_file(args[3][:], file.to_document().encode(), create_mode=CreateNew)
    println("created semantically repacked HDF5 file")
    return
  }
  if args.length() != 3 || !["read", "write-demo"].contains(args[1]) {
    raise Failure("usage: moonh5 read FILE.h5 | write-demo NEW.h5")
  }
  if args[1] == "write-demo" {
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
