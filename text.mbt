// SPDX-License-Identifier: GPL-2.0-only
// Port of the UTF-8, dynamic-size subset of boofuzz primitives/string.py and delim.py.

///|
pub fn Field::delimiter(
  value : String,
  fuzzable? : Bool = true,
  fuzz_values? : Array[Bytes] = [],
) -> Field {
  let encoded = @utf8.encode(value)
  let candidates : Array[TextCandidate] = []
  for n in [2, 5, 10, 25, 100, 500, 1000] {
    candidates.push(Repeated(encoded, n, 0))
  }
  candidates.push(Literal(b""))
  if value == " " {
    for n in [1, 2, 100] {
      candidates.push(Repeated(b"\t", n, 0))
    }
  }
  for
    text in [
      " ",
      "\t",
      "\t ".repeat(100),
      "\t\r\n".repeat(100),
      "!",
      "@",
      "#",
      "$",
      "%",
      "^",
      "&",
      "*",
      "(",
      ")",
      "{",
      "}",
      "[",
      "]",
      "-",
      "_",
      "+",
      "=",
      ":",
      ": ".repeat(100),
      ":7".repeat(100),
      ";",
      "'",
      "\"",
      "/",
      "\\",
      "?",
      "<",
      ">",
      ".",
      ",",
      "\r",
      "\n",
      "\r\n".repeat(64),
      "\r\n".repeat(128),
      "\r\n".repeat(512),
    ] {
    candidates.push(Literal(@utf8.encode(text)))
  }
  let base : Field = {
    value: encoded,
    count: if fuzzable {
      candidates.length()
    } else {
      0
    },
    candidate: i => candidates[i].render(),
    candidate_length: i => candidates[i].length(),
  }
  Field::with_fuzz_values(base, fuzz_values, fuzzable)
}

///|
enum TextCandidate {
  Literal(Bytes)
  Repeated(Bytes, Int, Int) // whole repetitions plus prefix length in bytes
  Terminator(Int, Int)
} derive(Eq)

///|
fn TextCandidate::render(self : TextCandidate) -> Bytes {
  match self {
    Literal(b) => b
    Repeated(seed, copies, prefix) =>
      seed.repeat(copies) + seed[:prefix].to_owned()
    Terminator(size, position) =>
      b"D".repeat(position) + b"\x00" + b"D".repeat(size - position - 1)
  }
}

///|
fn TextCandidate::length(self : TextCandidate) -> Int64 {
  match self {
    Literal(bytes) => bytes.length().to_int64()
    Repeated(bytes, copies, prefix) =>
      bytes.length().to_int64() * copies.to_int64() + prefix.to_int64()
    Terminator(size, _) => size.to_int64()
  }
}

///|
/// UTF-8 bad-string library, variable repeats and deterministic long strings.
/// Only dynamic size is supported. Enforce wire-byte limits at request rendering.
pub fn Field::text(
  value : String,
  fuzzable? : Bool = true,
  fuzz_values? : Array[Bytes] = [],
) -> Field {
  let encoded = @utf8.encode(value)
  let candidates : Array[TextCandidate] = []
  for text in string_library {
    candidates.push(Literal(@utf8.encode(text)))
  }
  let max_library_chars = string_library.fold(init=0, (n, item) => {
    n.max(item.length())
  })
  for n in [2, 10, 100] {
    if value.length() > max_library_chars / n ||
      !string_library.contains(value.repeat(n)) {
      candidates.push(Repeated(encoded, n, 0))
    }
  }
  let lengths = [8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 32768, 65535]
  for seed in string_seeds {
    let bytes = @utf8.encode(seed)
    for length in lengths {
      for delta in -2..<3 {
        let n = length + delta
        candidates.push(Repeated(bytes, n / seed.length(), n % seed.length()))
      }
    }
    for n in [99999, 100000, 500000, 1000000] {
      candidates.push(Repeated(bytes, n / seed.length(), n % seed.length()))
    }
  }
  for i, length in lengths {
    for position in string_null_indices[i] {
      candidates.push(Terminator(length, position))
    }
  }
  // With no max_len the only possible adjacent equality lies in literal entries.
  let unique : Array[TextCandidate] = []
  for candidate in candidates {
    if unique.last() != Some(candidate) {
      unique.push(candidate)
    }
  }
  let base : Field = {
    value: encoded,
    count: if fuzzable {
      unique.length()
    } else {
      0
    },
    candidate: fn(i) { unique[i].render() },
    candidate_length: i => unique[i].length(),
  }
  Field::with_fuzz_values(base, fuzz_values, fuzzable)
}
