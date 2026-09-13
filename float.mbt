// SPDX-License-Identifier: GPL-2.0-only
// Port of boofuzz/primitives/float.py at 518c13904fc32e7f2cc88c9dec934e509062953e.
// Upstream with seed=None relies on the process-global RNG (not reproducible);
// the port fixes the sequence seed at 0 in that case so indexed candidate
// access stays positionally stable. Only the "%.Nf" format subset is supported.

///|
/// Float candidates: the first mutation is the default value formatted with
/// s_format, the rest draw random.uniform(f_min, f_max) from the seeded
/// MT19937 stream; adjacent duplicates are dropped exactly like upstream,
/// where the uniform draw is consumed before the dedup check so the
/// remaining sequence matches upstream's generator. The candidate count is
/// the number of formatted values actually produced, whereas upstream
/// num_mutations keeps claiming max_mutations.
pub fn Field::float(
  default_value? : Double = 0.0,
  s_format? : String = ".1f",
  f_min? : Double = 0.0,
  f_max? : Double = 100.0,
  max_mutations? : Int = 1000,
  seed? : Int64,
  encode_as_ieee_754? : Bool = false,
  endian? : Endian = Big,
  fuzzable? : Bool = true,
  fuzz_values? : Array[Bytes] = [],
) -> Field raise ModelError {
  guard max_mutations >= 0 else { raise Invalid("negative max_mutations") }
  guard f_min <= f_max else { raise Invalid("float range: f_min > f_max") }
  let precision = parse_float_precision(s_format)
  let encode = fn(text : String) -> Bytes raise ModelError {
    if encode_as_ieee_754 {
      encode_float_ieee_754(parse_decimal(text), endian)
    } else {
      ascii_bytes(text)
    }
  }
  let value = encode(python_str_double(default_value))
  let generator = Mt19937::from_seed(seed.unwrap_or(0L))
  let saved : Array[Bytes] = []
  let mut last : String? = None
  for i in 0..<max_mutations {
    let raw = if i == 0 {
      default_value
    } else {
      generator.uniform(f_min, f_max)
    }
    let text = format_fixed_point(raw, precision)
    if last != Some(text) {
      last = Some(text)
      saved.push(encode(text))
    }
  }
  let base : Field = {
    value,
    count: if fuzzable {
      saved.length()
    } else {
      0
    },
    candidate: fn(i) { saved[i] },
    candidate_length: i => saved[i].length().to_int64(),
  }
  Field::with_fuzz_values(base, fuzz_values, fuzzable)
}

///|
/// Accept only Python "%[.N]f" specifiers (with or without a leading dot).
fn parse_float_precision(s_format : String) -> Int raise ModelError {
  let body = if s_format.has_prefix(".") { s_format[1:] } else { s_format }
  guard body.has_suffix("f") else { raise Invalid("float format must be %.Nf") }
  let mut precision = 0
  for i in 0..<(body.length() - 1) {
    let code = body[i].to_int() - 48
    guard code >= 0 && code <= 9 else {
      raise Invalid("float format must be %.Nf")
    }
    precision = precision * 10 + code
  }
  precision
}

///|
fn double_infinity() -> Double {
  0x7ff0000000000000UL.reinterpret_as_double()
}

///|
fn double_nan() -> Double {
  0x7ff8000000000000UL.reinterpret_as_double()
}

///|
/// CPython str(float): integral values print with a trailing ".0".
fn python_str_double(value : Double) -> String {
  let bits = value.reinterpret_as_uint64()
  if bits << 1 == 0UL {
    return if bits >> 63 == 1UL { "-0.0" } else { "0.0" }
  }
  if ((bits >> 52) & 0x7ffUL) == 0x7ffUL {
    return if bits << 12 != 0UL {
      "nan"
    } else if bits >> 63 == 1UL {
      "-inf"
    } else {
      "inf"
    }
  }
  let text = value.to_string()
  if text.contains(".") || text.contains("e") || text.contains("E") {
    text
  } else {
    text + ".0"
  }
}

///|
/// "%.Nf" fixed-point formatting with CPython printf semantics (round
/// half-to-even on the scaled value). Values are expected in the ranges
/// reachable from typical f_min/f_max; exponent-style output is not produced.
fn format_fixed_point(value : Double, precision : Int) -> String {
  let bits = value.reinterpret_as_uint64()
  let zeros = if precision > 0 { "." + "0".repeat(precision) } else { "" }
  if bits << 1 == 0UL {
    return if bits >> 63 == 1UL { "-0" + zeros } else { "0" + zeros }
  }
  if ((bits >> 52) & 0x7ffUL) == 0x7ffUL {
    return if bits >> 63 == 1UL { "-inf" } else { "inf" }
  }
  let negative = bits >> 63 == 1UL
  let magnitude = if negative { -value } else { value }
  let mut scale = 1.0
  for _ in 0..<precision {
    scale = scale * 10.0
  }
  let scaled = magnitude * scale
  let floored = scaled.floor()
  let fraction = scaled - floored
  let mut rounded = floored.to_int64()
  if fraction > 0.5 || (fraction == 0.5 && rounded % 2L != 0L) {
    rounded += 1L
  }
  let digits = rounded.to_string()
  let body = if precision == 0 {
    digits
  } else {
    let padding = if digits.length() <= precision {
      "0".repeat(precision + 1 - digits.length())
    } else {
      ""
    }
    let padded = padding + digits
    let cut = padded.length() - precision
    padded[:cut].to_owned() + "." + padded[cut:].to_owned()
  }
  if negative {
    "-" + body
  } else {
    body
  }
}

///|
/// Correctly-rounded decimal parse for the "%.Nf" output subset plus the
/// inf/nan spellings that survive Python's float(value) round trip.
/// The full digit string is accumulated as an integer and divided once, so
/// the result matches CPython's strtod for the short literals produced by
/// fixed-point formatting.
fn parse_decimal(text : String) -> Double raise ModelError {
  if text == "inf" {
    return double_infinity()
  }
  if text == "nan" {
    return double_nan()
  }
  let negative = text.has_prefix("-")
  let mut mantissa : Int64 = 0L
  let mut fraction_digits = 0
  let mut seen_dot = false
  let mut seen_digit = false
  for i in 0..<text.length() {
    let code = text[i].to_int()
    if i == 0 && (code == 45 || code == 43) {
      continue
    }
    if code == 46 {
      guard !seen_dot else { raise Invalid("bad float literal") }
      seen_dot = true
      continue
    }
    let digit = code - 48
    guard digit >= 0 && digit <= 9 else { raise Invalid("bad float literal") }
    seen_digit = true
    guard mantissa < 922337203685477580L else {
      raise Invalid("float literal exceeds precision support")
    }
    mantissa = mantissa * 10L + digit.to_int64()
    if seen_dot {
      fraction_digits += 1
    }
  }
  guard seen_digit else { raise Invalid("bad float literal") }
  let mut denominator = 1.0
  for _ in 0..<fraction_digits {
    denominator = denominator * 10.0
  }
  let value = mantissa.to_double() / denominator
  if negative {
    -value
  } else {
    value
  }
}

///|
fn ascii_bytes(text : String) -> Bytes {
  let bytes : Array[Byte] = []
  for ch in text {
    let code = ch.to_int()
    guard code >= 0 && code <= 127 else { continue }
    bytes.push(code.to_byte())
  }
  Bytes::from_array(bytes)
}

///|
/// Pack a Double as IEEE 754 binary32 with round-to-nearest-even, matching
/// the C double-to-float conversion used by struct.pack(">f"/"<f", value).
fn encode_float_ieee_754(value : Double, endian : Endian) -> Bytes {
  let bits = value.reinterpret_as_uint64()
  let sign = (bits >> 63 << 31).to_uint() & 0x80000000U
  let exponent = ((bits >> 52) & 0x7ffUL).to_int()
  let mantissa = bits & 0xfffffffffffffUL
  let packed : UInt = if exponent == 0x7ff {
    if mantissa == 0UL {
      sign | 0x7f800000U
    } else {
      sign | 0x7fc00000U
    }
  } else if exponent == 0 && mantissa == 0UL {
    sign
  } else {
    // Full significand with the implicit bit, aligned for a 23-bit field.
    let full = mantissa | 0x10000000000000UL
    let biased = exponent - 896
    if biased >= 0xff {
      sign | 0x7f800000U
    } else if biased > 0 {
      let dropped = full & 0x1fffffffUL
      let mut kept = (full >> 29).to_uint()
      let mut exp = biased.reinterpret_as_uint()
      if dropped > 0x10000000UL ||
        (dropped == 0x10000000UL && (kept & 1U) == 1U) {
        kept += 1U
        if kept == 0x800000U {
          kept = 0U
          exp += 1U
        }
      }
      sign | (exp << 23) | (kept & 0x7fffffU)
    } else {
      // Subnormal or zero in binary32.
      let shift = 926 - exponent
      let mut kept : UInt = 0U
      if shift <= 53 {
        let quotient = full >> shift
        let remainder = full & ((1UL << shift) - 1UL)
        let half = 1UL << (shift - 1)
        let mut result = quotient.to_uint()
        if remainder > half || (remainder == half && (quotient & 1UL) == 1UL) {
          result += 1U
        }
        if result == 0x800000U {
          // Rounded up into the smallest normal exponent.
          return encode_integer((sign | (1U << 23)).to_uint64(), 32, endian)
        }
        kept = result
      }
      sign | kept
    }
  }
  encode_integer(packed.to_uint64(), 32, endian)
}
