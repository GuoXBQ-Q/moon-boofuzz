///|
pub(all) suberror RecordError {
  Invalid(String)
  UnsupportedVersion(Int)
} derive(Debug)

///|
pub extend RecordError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn hex_encode(bytes : Bytes) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let result = StringBuilder()
  for byte in bytes {
    result.write_char(digits[byte.to_int() / 16])
    result.write_char(digits[byte.to_int() % 16])
  }
  result.to_string()
}

///|
fn digit(c : UInt16) -> Int raise RecordError {
  if c >= '0' && c <= '9' {
    c.to_int() - 48
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 97 + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 65 + 10
  } else {
    raise Invalid("invalid hexadecimal byte")
  }
}

///|
pub fn hex_decode(text : String) -> Bytes raise RecordError {
  guard text.length() % 2 == 0 else { raise Invalid("odd hexadecimal length") }
  Bytes::makei(text.length() / 2, i => {
    (digit(text[i * 2]) * 16 + digit(text[i * 2 + 1])).to_byte()
  })
}
