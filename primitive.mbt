///|
/// Explicit byte fields. Automatic boundary mutations are planned.
pub(all) enum Primitive {
  Static(Bytes)
  Choice(Bytes, Array[Bytes])
} derive(Debug)

///|
pub extend Primitive with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Return the normal wire value.
pub fn Primitive::default_value(self : Primitive) -> Bytes {
  match self {
    Static(value) | Choice(value, _) => value
  }
}

///|
/// Explicit alternatives in caller order; duplicates are preserved.
pub fn Primitive::mutations(self : Primitive) -> Array[Bytes] {
  match self {
    Static(_) => []
    Choice(_, values) => values.copy()
  }
}
