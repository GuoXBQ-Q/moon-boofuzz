// SPDX-License-Identifier: GPL-2.0-only
// Port of boofuzz/primitives/random_data.py at 518c13904fc32e7f2cc88c9dec934e509062953e.
// Upstream seeds a fresh random.Random(0) per mutations() call for
// reproducibility; the port materializes the same MT19937 sequence eagerly
// so indexed candidate access stays positionally stable.

///|
/// Random data candidates from upstream's deterministic Random(0) stream.
/// Step mode fixes each length at min_length + i*step without consuming the
/// generator; otherwise each candidate draws one randint for its length and
/// one randint(0, 255) per byte. Candidate identity is stable, so the
/// upstream count quirk (mutations loop over get_num_mutations, which also
/// counts fuzz_values) is intentionally not reproduced: the random sequence
/// has exactly max_mutations entries and user fuzz_values are appended after.
pub fn Field::random_data(
  default_value? : Bytes = b"",
  min_length? : Int = 0,
  max_length? : Int = 1,
  max_mutations? : Int = 25,
  step? : Int,
  fuzzable? : Bool = true,
  fuzz_values? : Array[Bytes] = [],
) -> Field raise ModelError {
  guard min_length >= 0 && max_length >= min_length else {
    raise Invalid("invalid random data length range")
  }
  guard max_mutations >= 0 else { raise Invalid("negative max_mutations") }
  let step_value = step.unwrap_or(0)
  guard step_value >= 0 else { raise Invalid("negative random data step") }
  let count = if step_value > 0 {
    (max_length - min_length) / step_value + 1
  } else {
    max_mutations
  }
  let generator = Mt19937::from_seed(0L)
  let saved : Array[Bytes] = []
  let mut total_bytes = 0L
  for i in 0..<count {
    let length = if step_value > 0 {
      min_length + i * step_value
    } else {
      generator.randint(min_length, max_length)
    }
    total_bytes += length.to_int64()
    guard total_bytes <= 20000000L else {
      raise Invalid("random data candidates exceed the byte budget")
    }
    let bytes = Bytes::makei(length, _ => generator.randint(0, 255).to_byte())
    saved.push(bytes)
  }
  let base : Field = {
    value: default_value,
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
