// SPDX-License-Identifier: GPL-2.0-only
// Adapted from boofuzz/primitives/bit_field.py at 518c13904fc32e7f2cc88c9dec934e509062953e.

///|
pub(all) enum Endian {
  Little
  Big
} derive(Debug, Eq)

///|
fn integer_max(width : Int) -> UInt64 raise ModelError {
  guard width == 8 || width == 16 || width == 32 || width == 64 else {
    raise Invalid("integer width must be 8, 16, 32 or 64")
  }
  if width == 64 {
    0xffffffffffffffffUL
  } else {
    (1UL << width) - 1UL
  }
}

///|
fn encode_integer(value : UInt64, width : Int, endian : Endian) -> Bytes {
  Bytes::makei(width / 8, fn(i) {
    let shift = match endian {
      Little => i * 8
      Big => width - 8 - i * 8
    }
    ((value >> shift) & 255UL).to_byte()
  })
}

///|
/// Unsigned binary integers with upstream's sorted, deduplicated +/-10 boundaries.
/// Width is in bits. ASCII, full_range and custom max_num are not supported.
pub fn Field::integer(
  value : UInt64,
  width? : Int = 8,
  endian? : Endian = Little,
  fuzzable? : Bool = true,
) -> Field raise ModelError {
  let maximum = integer_max(width)
  guard value <= maximum else { raise Invalid("integer default out of range") }
  let candidates : Array[UInt64] = []
  let boundaries : Array[UInt64] = [0UL]
  // Compute floor(2^width / divisor) without ever representing 2^64.
  for divisor in [32UL, 16UL, 8UL, 4UL, 3UL, 2UL] {
    let carry = if maximum % divisor == divisor - 1UL { 1UL } else { 0UL }
    boundaries.push(maximum / divisor + carry)
  }
  for boundary in boundaries {
    for delta in -10..<10 {
      let magnitude = (if delta < 0 { -delta } else { delta }).to_uint64()
      if delta < 0 && boundary < magnitude {
        continue
      }
      if delta >= 0 && maximum - boundary < magnitude {
        continue
      }
      let candidate = if delta < 0 {
        boundary - magnitude
      } else {
        boundary + magnitude
      }
      if candidates.last().map(fn(last) { candidate > last }).unwrap_or(true) {
        candidates.push(candidate)
      }
    }
  }
  // Last upstream boundary is 2^width, and only its ten lower neighbors fit.
  for delta in 0..<10 {
    let candidate = maximum - (9 - delta).to_uint64()
    if candidates.last().map(fn(last) { candidate > last }).unwrap_or(true) {
      candidates.push(candidate)
    }
  }
  {
    value: encode_integer(value, width, endian),
    count: if fuzzable {
      candidates.length()
    } else {
      0
    },
    candidate: fn(i) { encode_integer(candidates[i], width, endian) },
    candidate_length: _ => (width / 8).to_int64(),
  }
}
