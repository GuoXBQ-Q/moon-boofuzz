// SPDX-License-Identifier: GPL-2.0-only
// Port of boofuzz/primitives/float.py at 518c13904fc32e7f2cc88c9dec934e509062953e.
// Upstream with seed=None relies on the process-global RNG (not reproducible);
// the port fixes the sequence seed at 0 in that case so indexed candidate
// access stays positionally stable. Only the CPython "%.Nf" format subset is
// supported ("f" defaults to six digits like "%f"), rendered with exact
// decimal rounding of the double, matching CPython printf output.

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
/// Accept only Python "%[.N]f" specifiers: bare "f" (CPython's "%f" default
/// precision of 6), ".f" (precision 0) and ".Nf". Digits without a leading
/// dot are width/flag characters in CPython, never precision, so they are
/// rejected instead of misread.
fn parse_float_precision(s_format : String) -> Int raise ModelError {
  guard s_format.has_suffix("f") else {
    raise Invalid("float format must be %.Nf")
  }
  if !s_format.has_prefix(".") {
    guard s_format == "f" else { raise Invalid("float format must be %.Nf") }
    return 6
  }
  let mut precision = 0
  for i in 1..<(s_format.length() - 1) {
    let code = s_format[i].to_int() - 48
    guard code >= 0 && code <= 9 else {
      raise Invalid("float format must be %.Nf")
    }
    precision = precision * 10 + code
    // Keep absurd precision specs from ballooning the exact-arithmetic
    // workload; CPython has no limit but a fuzz payload never needs it.
    guard precision <= 1_000_000 else {
      raise Invalid("float format precision too large")
    }
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
/// "%.Nf" fixed-point formatting with CPython printf semantics: the exact
/// binary value of the double is rounded to N decimal digits exactly once,
/// round-half-to-even on the exact value. Midpoints such as 0.05 with
/// "%.1f" therefore render like CPython ("0.1": the double is strictly
/// above the decimal midpoint) instead of double rounding through a scaled
/// double, which would print "0.0".
fn format_fixed_point(value : Double, precision : Int) -> String {
  let bits = value.reinterpret_as_uint64()
  let zeros = if precision > 0 { "." + "0".repeat(precision) } else { "" }
  if bits << 1 == 0UL {
    return if bits >> 63 == 1UL { "-0" + zeros } else { "0" + zeros }
  }
  if ((bits >> 52) & 0x7ffUL) == 0x7ffUL {
    if bits << 12 != 0UL {
      return if bits >> 63 == 1UL { "-nan" } else { "nan" }
    }
    return if bits >> 63 == 1UL { "-inf" } else { "inf" }
  }
  let negative = bits >> 63 == 1UL
  let magnitude = if negative { -value } else { value }
  // magnitude = m * 2^k with m a 53-bit integer (subnormals keep their
  // raw fraction and the minimum exponent).
  let raw = magnitude.reinterpret_as_uint64()
  let biased = ((raw >> 52) & 0x7ffUL).to_int()
  let (m, k) = if biased == 0 {
    (raw & 0xfffffffffffffUL, -1074)
  } else {
    ((raw & 0xfffffffffffffUL) | 0x10000000000000UL, biased - 1075)
  }
  // digits = round_half_even(m * 10^N * 2^k), computed exactly.
  let scaled = big_from_u64(m)
  for _ in 0..<precision {
    big_mul_small(scaled, 10U)
  }
  if k >= 0 {
    big_shl(scaled, k)
  } else {
    let j = -k
    // Divisor 2^j: r > half iff any bit below j-1 is set; r == half iff
    // bit j-1 is set and no lower bit is. Ties round to even, so the tie
    // bit alone rounds up only when the quotient (bit j of the scaled
    // value) is odd.
    let round_up = big_bit(scaled, j - 1) &&
      (big_any_bit_below(scaled, j - 1) || big_bit(scaled, j))
    big_shr(scaled, j)
    if round_up {
      big_add_one(scaled)
    }
  }
  let digits = big_to_decimal(scaled)
  let body = if precision == 0 {
    digits
  } else {
    let padded = if digits.length() <= precision {
      "0".repeat(precision + 1 - digits.length()) + digits
    } else {
      digits
    }
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
/// Little-endian base-2^32 limb scratch values for the exact %.Nf
/// rounding above; magnitudes stay under ~1200 bits, so small arrays
/// cover every double.
fn big_from_u64(v : UInt64) -> Array[UInt] {
  [v.to_uint(), (v >> 32).to_uint()]
}

///|
fn big_mul_small(a : Array[UInt], m : UInt) -> Unit {
  let mut carry : UInt64 = 0UL
  for i in 0..<a.length() {
    let t = a[i].to_uint64() * m.to_uint64() + carry
    a[i] = t.to_uint()
    carry = t >> 32
  }
  if carry != 0UL {
    a.push(carry.to_uint())
  }
}

///|
fn big_bit(a : Array[UInt], i : Int) -> Bool {
  let limb = i / 32
  if limb >= a.length() {
    return false
  }
  ((a[limb] >> (i % 32)) & 1U) == 1U
}

///|
/// Whether any bit strictly below position i is set.
fn big_any_bit_below(a : Array[UInt], i : Int) -> Bool {
  let limb = i / 32
  for j in 0..<limb {
    if j < a.length() && a[j] != 0U {
      return true
    }
  }
  if limb < a.length() {
    let mask = (1U << (i % 32)) - 1U
    if (a[limb] & mask) != 0U {
      return true
    }
  }
  false
}

///|
fn big_shl(a : Array[UInt], bits : Int) -> Unit {
  if bits == 0 {
    return
  }
  let words = bits / 32
  let off = bits % 32
  let n = a.length()
  for _ in 0..<(words + 1) {
    a.push(0U)
  }
  let total = a.length()
  if off == 0 {
    for i = total - 1; i >= 0; i = i - 1 {
      a[i] = if i - words >= 0 && i - words < n { a[i - words] } else { 0U }
    }
    return
  }
  // Written right to left so the sources are never overwritten first.
  for i = total - 1; i >= 0; i = i - 1 {
    let src = i - words
    let mut v : UInt64 = 0UL
    if src >= 1 && src - 1 < n {
      v = a[src - 1].to_uint64() >> (32 - off)
    }
    if src >= 0 && src < n {
      v = v | (a[src].to_uint64() << off)
    }
    a[i] = v.to_uint()
  }
}

///|
fn big_shr(a : Array[UInt], bits : Int) -> Unit {
  let words = bits / 32
  let off = bits % 32
  let n = a.length()
  if words >= n {
    for i in 0..<n {
      a[i] = 0U
    }
    return
  }
  if off == 0 {
    for i in 0..<(n - words) {
      a[i] = a[i + words]
    }
  } else {
    for i in 0..<(n - words) {
      let mut v = (a[i + words].to_uint64() >> off).to_uint()
      if i + words + 1 < n {
        v = v | (a[i + words + 1].to_uint64() << (32 - off)).to_uint()
      }
      a[i] = v
    }
  }
  for i in (n - words)..<n {
    a[i] = 0U
  }
}

///|
fn big_add_one(a : Array[UInt]) -> Unit {
  for i in 0..<a.length() {
    let t = a[i].to_uint64() + 1UL
    a[i] = t.to_uint()
    if t <= 0xffffffffUL {
      return
    }
  }
  a.push(1U)
}

///|
/// Decimal digits of the limb value, via repeated division by 10^9.
fn big_to_decimal(a : Array[UInt]) -> String {
  let mut n = a.length()
  while n > 1 && a[n - 1] == 0U {
    n -= 1
  }
  if n == 1 && a[0] == 0U {
    return "0"
  }
  let groups : Array[String] = []
  while n > 1 || a[n - 1] != 0U {
    let mut rem : UInt64 = 0UL
    for i = n - 1; i >= 0; i = i - 1 {
      let cur = (rem << 32) | a[i].to_uint64()
      a[i] = (cur / 1000000000UL).to_uint()
      rem = cur % 1000000000UL
    }
    groups.push(rem.to_string())
    while n > 1 && a[n - 1] == 0U {
      n -= 1
    }
  }
  let mut text = groups[groups.length() - 1]
  for i = groups.length() - 2; i >= 0; i = i - 1 {
    text = text + "0".repeat(9 - groups[i].length()) + groups[i]
  }
  text
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
