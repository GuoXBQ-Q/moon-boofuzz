///|
/// A flat request. Nested blocks and computed fields are planned.
pub struct Request {
  fields : Array[Primitive]
}

///|
/// Snapshot caller-owned field definitions.
pub fn Request::new(fields : Array[Primitive]) -> Request {
  {
    fields: fields.map(fn(field) {
      match field {
        Static(value) => Static(value)
        Choice(value, alternatives) => Choice(value, alternatives.copy())
      }
    }),
  }
}

///|
/// Render the normal request without text decoding.
pub fn Request::render(self : Request) -> Bytes {
  let output : Array[Byte] = []
  for field in self.fields {
    for byte in field.default_value() {
      output.push(byte)
    }
  }
  Bytes::from_array(output)
}

///|
/// Generate one-field-at-a-time cases in field and alternative order.
/// Materializes all cases; intended for small explicit mutation sets.
pub fn Request::mutations(self : Request) -> Array[Bytes] {
  let cases : Array[Bytes] = []
  for field_index, field in self.fields {
    for alternative in field.mutations() {
      let output : Array[Byte] = []
      for index, other in self.fields {
        let value = if index == field_index {
          alternative
        } else {
          other.default_value()
        }
        for byte in value {
          output.push(byte)
        }
      }
      cases.push(Bytes::from_array(output))
    }
  }
  cases
}
