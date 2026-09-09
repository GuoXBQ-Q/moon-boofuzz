// SPDX-License-Identifier: GPL-2.0-only
// Adapted from boofuzz/primitives/bytes.py at 518c13904fc32e7f2cc88c9dec934e509062953e.

///|
let magic_bytes : Array[Bytes] = [
  b"\x00\x00\x81\x23", b"\x00\xfa\xca\xde", b"\x1b\xad\xb0\x02", b"\x8b\xad\xf0\x0d",
  b"\xa5\xa5\xa5\xa5", b"\xa5", b"\xab\xab\xab\xab", b"\xab\xad\xba\xbe", b"\xab\xba\xba\xbe",
  b"\xab\xad\xca\xfe", b"\xb1\x6b\x00\xb5", b"\xba\xad\xf0\x0d", b"\xba\xaa\xaa\xad",
  b"\xba\xd2\x22\x22", b"\xba\xdb\xad\xba\xdb\xad", b"\xba\xdc\x0f\xfe\xe0\xdd\xf0\x0d",
  b"\xba\xdd\xca\xfe", b"\xbb\xad\xbe\xef", b"\xbe\xef\xca\xce", b"\xc0\x00\x10\xff",
  b"\xca\xfe\xba\xbe", b"\xca\xfe\xd0\x0d", b"\xca\xfe\xfe\xed", b"\xcc\xcc\xcc\xcc",
  b"\xcd\xcd\xcd\xcd", b"\x0d\x15\xea\x5e", b"\xdd\xdd\xdd\xdd", b"\xde\xad\x10\xcc",
  b"\xde\xad\xba\xbe", b"\xde\xad\xbe\xef", b"\xde\xad\xca\xfe", b"\xde\xad\xc0\xde",
  b"\xde\xad\xfa\x11", b"\xde\xad\xf0\x0d", b"\xde\xfe\xc8\xed", b"\xde\xad\xde\xad",
  b"\xeb\xeb\xeb\xeb", b"\xfa\xde\xde\xad", b"\xfd\xfd\xfd\xfd", b"\xfe\xe1\xde\xad",
  b"\xfe\xed\xfa\xce", b"\xfe\xee\xfe\xee",
]

///|
fn byte_replacements(width : Int) -> Array[Bytes] {
  let values = match width {
    1 => [b"\x00", b"\x01", b"\x7f", b"\x80", b"\xff"]
    2 =>
      [
        b"\x00\x00", b"\x01\x00", b"\x00\x01", b"\x7f\xff", b"\xff\x7f", b"\xfe\xff",
        b"\xff\xfe", b"\xff\xff",
      ]
    _ =>
      [
        b"\x00\x00\x00\x00", b"\x00\x00\x00\x01", b"\x01\x00\x00\x00", b"\x7f\xff\xff\xff",
        b"\xff\xff\xff\x7f", b"\xfe\xff\xff\xff", b"\xff\xff\xff\xfe", b"\xff\xff\xff\xff",
      ]
  }
  for item in magic_bytes {
    if item.length() == width {
      values.push(item)
    }
  }
  values
}

///|
/// Binary mutation candidates are materialized individually on indexed access.
/// Size/max_len adjust mutations only, matching upstream; default stays verbatim.
/// Padding is restricted to exactly one byte.
pub fn Field::binary(
  value : Bytes,
  size? : Int,
  max_len? : Int,
  padding? : Bytes = b"\x00",
  fuzzable? : Bool = true,
) -> Field raise ModelError {
  guard padding.length() == 1 else {
    raise Invalid("binary padding must be one byte")
  }
  for limit in [size, max_len] {
    if limit is Some(n) && n < 0 {
      raise Invalid("negative byte length")
    }
  }
  // Count arithmetic and repeat lengths must fit Int even before execution limits.
  guard value.length() <= 20000000 else {
    raise Invalid("binary field too large")
  }
  let replacements = [
    byte_replacements(1),
    byte_replacements(2),
    byte_replacements(4),
  ]
  let widths = [1, 2, 4]
  let mut count = 12 + magic_bytes.length()
  for i, width in widths {
    count += (value.length() - width + 1).max(0) * replacements[i].length()
  }
  let adjust = fn(candidate : Bytes) {
    match size {
      Some(n) =>
        if candidate.length() > n {
          candidate[:n].to_owned()
        } else {
          candidate + padding.repeat(n - candidate.length())
        }
      None =>
        match max_len {
          Some(n) if candidate.length() > n => candidate[:n].to_owned()
          _ => candidate
        }
    }
  }
  {
    value,
    count: if fuzzable {
      count
    } else {
      0
    },
    candidate: fn(index) {
      let raw = if index < 9 {
        match index {
          0 => b""
          1 => b"\x00"
          2 => b"\xff"
          _ => b"A".repeat([10, 100, 1000, 5000, 10000, 100000][index - 3])
        }
      } else if index < 12 {
        value.repeat([2, 10, 100][index - 9])
      } else if index < 12 + magic_bytes.length() {
        magic_bytes[index - 12]
      } else {
        for i = 0, offset = index - 12 - magic_bytes.length(); i < 3; {
          let library = replacements[i]
          let n = (value.length() - widths[i] + 1).max(0) * library.length()
          if offset < n {
            let position = offset / library.length()
            break value[:position].to_owned() +
              library[offset % library.length()] +
              value[position + widths[i]:].to_owned()
          }
          continue i + 1, offset - n
        } nobreak {
          value
        }
      }
      adjust(raw)
    },
  }
}
