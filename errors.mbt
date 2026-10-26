///|
/// Errors carry a byte offset when caused by an on-disk encoding.
pub suberror H5Error {
  Invalid(String, Int32)
  Unsupported(String, Int32)
  Limit(String)
  NotFound(String)
} derive(Debug, Eq)

///|
pub extend H5Error with @debug.Debug::{to_repr}

///|
pub extend H5Error with Eq::{equal, not_equal}

///|
/// Hard bounds apply before allocation or traversal, even for trusted input.
pub(all) struct Limits {
  max_file_bytes : Int32
  max_elements : Int32
  max_metadata_bytes : Int32
  max_objects : Int32
  max_depth : Int32
  max_rank : Int32
} derive(Debug, Eq)

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

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
  if self.max_file_bytes < 0 ||
    self.max_elements < 0 ||
    self.max_metadata_bytes < 0 ||
    self.max_objects <= 0 ||
    self.max_depth <= 0 ||
    self.max_rank <= 0 {
    raise Invalid("negative or empty resource limit", 0)
  }
}

///|
fn checked_add(a : Int32, b : Int32) -> Int32 raise H5Error {
  if a < 0 || b < 0 || a > 2147483647 - b {
    raise Limit("integer addition")
  }
  a + b
}

///|
fn checked_mul(a : Int32, b : Int32) -> Int32 raise H5Error {
  if a < 0 || b < 0 || (b != 0 && a > 2147483647 / b) {
    raise Limit("integer multiplication")
  }
  a * b
}
