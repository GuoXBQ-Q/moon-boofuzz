// SPDX-License-Identifier: GPL-2.0-only
// Port of boofuzz/primitives/from_file.py at 518c13904fc32e7f2cc88c9dec934e509062953e.
// The core package has no file IO, so callers read the file lines themselves;
// JSON users list the lines inline. Upstream's max_len>0 path deduplicates
// through a Python set, losing order; the port keeps first-occurrence order.

///|
/// Cycle through bad values, one per provided line. Empty lines are dropped
/// like upstream's filter(None, ...); max_len > 0 keeps only shorter lines.
/// Upstream collapses the filtered library through a Python set ONLY when at
/// least one line exceeds max_len (from_file.py:43-47), so the port applies
/// dedup under the same condition — keeping first-occurrence order where the
/// set would scramble it (documented deviation).
pub fn Field::from_lines(
  default_value? : Bytes = b"",
  lines? : Array[Bytes] = [],
  max_len? : Int = 0,
  fuzzable? : Bool = true,
  fuzz_values? : Array[Bytes] = [],
) -> Field raise ModelError {
  guard max_len >= 0 else { raise Invalid("negative max_len") }
  let oversized = max_len > 0 &&
    lines.iter().any(line => line.length() > max_len)
  let saved : Array[Bytes] = []
  let seen : Map[Bytes, Bool] = Map([])
  for line in lines {
    if line.is_empty() {
      continue
    }
    if max_len > 0 && line.length() > max_len {
      continue
    }
    if oversized {
      if seen.contains(line) {
        continue
      }
      seen[line] = true
    }
    saved.push(line)
  }
  Field::simple(default_value, saved, fuzzable~, fuzz_values~)
}
