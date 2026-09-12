///|
pub suberror ModelError {
  Invalid(String)
  Limit(String)
} derive(Debug)

///|
/// An immutable field definition with indexed, on-demand mutation generation.
pub struct Field {
  value : Bytes
  count : Int
  candidate : (Int) -> Bytes
  candidate_length : (Int) -> Int64
}

///|
pub fn Field::simple(
  value : Bytes,
  values : Array[Bytes],
  fuzzable? : Bool = true,
) -> Field {
  let saved = values.copy()
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
  Field::simple(value, saved, fuzzable~)
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
