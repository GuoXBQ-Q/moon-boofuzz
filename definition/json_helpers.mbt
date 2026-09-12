///|
pub(all) suberror DefinitionError {
  Invalid(String)
  UnsupportedVersion(Int)
} derive(Debug)

///|
fn property(value : Json, name : String) -> Json? {
  match value {
    Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn required(value : Json, name : String) -> Json raise DefinitionError {
  property(value, name).unwrap_or_else(() => {
    raise Invalid("missing property: " + name)
  })
}

///|
fn text(value : Json, name : String, default : String) -> String raise {
  match property(value, name) {
    Some(item) => @json.from_json(item)
    None => default
  }
}

///|
fn number(value : Json, name : String, default : Int) -> Int raise {
  match property(value, name) {
    Some(item) => @json.from_json(item)
    None => default
  }
}

///|
fn boolean(value : Json, name : String, default : Bool) -> Bool raise {
  match property(value, name) {
    Some(item) => @json.from_json(item)
    None => default
  }
}

///|
fn hexes(value : Json, name : String) -> Array[Bytes] raise {
  let strings : Array[String] = match property(value, name) {
    Some(item) => @json.from_json(item)
    None => []
  }
  strings.map(value => @records.hex_decode(value))
}

///|
pub fn decimal_u64(text : String) -> UInt64 raise DefinitionError {
  guard !text.is_empty() else { raise Invalid("empty unsigned integer") }
  for c in text; value = 0UL {
    guard c >= '0' && c <= '9' else {
      raise Invalid("expected unsigned decimal string")
    }
    let digit = (c.to_int() - 48).to_uint64()
    guard value <= (0xffffffffffffffffUL - digit) / 10UL else {
      raise Invalid("UInt64 overflow")
    }
    continue value * 10UL + digit
  } nobreak {
    value
  }
}

///|
fn unsigned_values(value : Json) -> Array[UInt64] raise {
  let strings : Array[String] = match property(value, "mutations") {
    Some(item) => @json.from_json(item)
    None => []
  }
  strings.map(decimal_u64)
}

///|
fn endian(value : Json) -> @core.Endian raise {
  match text(value, "endian", "little") {
    "little" => Little
    "big" => Big
    _ => raise Invalid("endian must be little or big")
  }
}
