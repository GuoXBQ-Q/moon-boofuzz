// SPDX-License-Identifier: GPL-2.0-only
// Port of the UTF-8, dynamic-size subset of boofuzz primitives/string.py and delim.py.

///|
pub fn Field::delimiter(value : String, fuzzable? : Bool = true) -> Field {
  let encoded = @utf8.encode(value)
  let candidates : Array[Bytes] = []
  for n in [2, 5, 10, 25, 100, 500, 1000] {
    candidates.push(encoded.repeat(n))
  }
  candidates.push(b"")
  if value == " " {
    for n in [1, 2, 100] {
      candidates.push(b"\t".repeat(n))
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
    candidates.push(@utf8.encode(text))
  }
  Field::simple(encoded, candidates, fuzzable~)
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
/// UTF-8 bad-string library, variable repeats and deterministic long strings.
/// Only dynamic size is supported. Enforce wire-byte limits at request rendering.
pub fn Field::text(value : String, fuzzable? : Bool = true) -> Field {
  let encoded = @utf8.encode(value)
  let candidates : Array[TextCandidate] = []
  for text in string_library {
    candidates.push(Literal(@utf8.encode(text)))
  }
  for n in [2, 10, 100] {
    let text = value.repeat(n)
    if !string_library.contains(text) {
      candidates.push(Literal(@utf8.encode(text)))
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
  {
    value: encoded,
    count: if fuzzable {
      unique.length()
    } else {
      0
    },
    candidate: fn(i) { unique[i].render() },
  }
}
