///|
pub suberror ModelError {
  Invalid(String)
  Limit(String)
} derive(Debug)

///|
pub extend ModelError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An immutable field definition with indexed, on-demand mutation generation.
pub struct Field {
  value : Bytes
  count : Int
  candidate : (Int) -> Bytes
  candidate_length : (Int) -> Int64
}

///|
/// Append user-supplied fuzz values after the built-in candidates with
/// continuous mutation indices, following boofuzz/fuzzable.py get_mutations
/// at 518c139 (fuzz_values chain after mutations(); index keeps incrementing).
/// Only applied when the field is fuzzable; disabled fields stay at zero.
fn Field::with_fuzz_values(
  base : Field,
  extra : Array[Bytes],
  fuzzable : Bool,
) -> Field {
  if !fuzzable || extra.is_empty() {
    return base
  }
  let saved = extra.copy()
  let base_count = base.count
  {
    value: base.value,
    count: base_count + saved.length(),
    candidate: fn(i) {
      if i < base_count {
        (base.candidate)(i)
      } else {
        saved[i - base_count]
      }
    },
    candidate_length: fn(i) {
      if i < base_count {
        (base.candidate_length)(i)
      } else {
        saved[i - base_count].length().to_int64()
      }
    },
  }
}

///|
pub fn Field::simple(
  value : Bytes,
  values : Array[Bytes],
  fuzzable? : Bool = true,
  fuzz_values? : Array[Bytes] = [],
) -> Field {
  let saved = values.copy()
  for item in fuzz_values {
    saved.push(item)
  }
  {
    value,
    count: if fuzzable {
      saved.length()
    } else {
      0
    },
    candidate: fn(i) { saved[i] },
    candidate_length: i => saved[i].length().to_int64(),
  }
}

///|
/// Group removes only the first occurrence of its default from candidates.
pub fn Field::group(
  values : Array[Bytes],
  default_value? : Bytes,
  fuzzable? : Bool = true,
  fuzz_values? : Array[Bytes] = [],
) -> Field raise ModelError {
  guard !values.is_empty() else { raise Invalid("empty group") }
  let value = default_value.unwrap_or(values[0])
  let saved : Array[Bytes] = []
  let mut removed = false
  for item in values {
    if !removed && item == value {
      removed = true
    } else {
      saved.push(item)
    }
  }
  let base = Field::simple(value, saved, fuzzable~)
  Field::with_fuzz_values(base, fuzz_values, fuzzable)
}

///|
pub fn Field::default_value(self : Field) -> Bytes {
  self.value
}

///|
pub fn Field::num_mutations(self : Field) -> Int {
  self.count
}

///|
pub fn Field::mutation(self : Field, index : Int) -> Bytes? {
  if index < 0 || index >= self.count {
    None
  } else {
    Some((self.candidate)(index))
  }
}
