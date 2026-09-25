// SPDX-License-Identifier: GPL-2.0-only
// application/x-www-form-urlencoded decoding for converter form posts.
// Percent escapes are resolved at byte level before UTF-8 decoding so
// multi-byte characters survive the round trip.

///|
fn parse_form(body : Bytes) -> Map[String, String] {
  let form : Map[String, String] = Map([])
  for raw_pair in @utf8.decode_lossy(body).split("&") {
    let pair = raw_pair.to_owned()
    if pair.is_empty() {
      continue
    }
    let (key, value) = match pair.find("=") {
      Some(index) => (pair[:index].to_owned(), pair[index + 1:].to_owned())
      None => (pair, "")
    }
    form[form_decode(key)] = form_decode(value)
  }
  form
}

///|
fn form_decode(text : String) -> String {
  let encoded = @utf8.encode(text)
  let decoded : Array[Int] = []
  let mut i = 0
  while i < encoded.length() {
    let byte = encoded[i].to_int()
    if byte == 43 {
      // "+" means a literal space in form encoding.
      decoded.push(32)
      i += 1
    } else if byte == 37 && i + 2 < encoded.length() {
      let high = hex_nibble(encoded[i + 1].to_int())
      let low = hex_nibble(encoded[i + 2].to_int())
      if high >= 0 && low >= 0 {
        decoded.push(high * 16 + low)
        i += 3
      } else {
        decoded.push(byte)
        i += 1
      }
    } else {
      decoded.push(byte)
      i += 1
    }
  }
  @utf8.decode_lossy(Bytes::makei(decoded.length(), i => decoded[i].to_byte()))
}

///|
fn hex_nibble(value : Int) -> Int {
  if value >= 48 && value <= 57 {
    value - 48
  } else if value >= 97 && value <= 102 {
    value - 87
  } else if value >= 65 && value <= 70 {
    value - 55
  } else {
    -1
  }
}
