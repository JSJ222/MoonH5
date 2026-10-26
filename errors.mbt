///| Errors carry a byte offset when caused by an on-disk encoding.
pub suberror H5Error {
  Invalid(String, Int)
  Unsupported(String, Int)
  Limit(String)
  NotFound(String)
} derive(Debug, Eq)

///| Hard bounds apply before allocation or traversal, even for trusted input.
pub(all) struct Limits {
  max_file_bytes : Int
  max_elements : Int
  max_metadata_bytes : Int
  max_objects : Int
  max_depth : Int
  max_rank : Int
} derive(Debug, Eq)

///|
pub fn Limits::default() -> Limits {
  {
    max_file_bytes: 268435456,
    max_elements: 16777216,
    max_metadata_bytes: 16777216,
    max_objects: 100000,
    max_depth: 64,
    max_rank: 32,
  }
}

///|
fn Limits::validate(self : Limits) -> Unit raise H5Error {
  if self.max_file_bytes < 0 || self.max_elements < 0 ||
    self.max_metadata_bytes < 0 || self.max_objects <= 0 ||
    self.max_depth <= 0 || self.max_rank <= 0 {
    raise Invalid("negative or empty resource limit", 0)
  }
}

///|
fn checked_add(a : Int, b : Int) -> Int raise H5Error {
  if a < 0 || b < 0 || a > 2147483647 - b { raise Limit("integer addition") }
  a + b
}

///|
fn checked_mul(a : Int, b : Int) -> Int raise H5Error {
  if a < 0 || b < 0 || (b != 0 && a > 2147483647 / b) {
    raise Limit("integer multiplication")
  }
  a * b
}
