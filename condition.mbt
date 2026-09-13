///|
/// Block visibility conditions, following boofuzz/blocks/block.py
/// `_do_dependencies_allow_render` at 518c13904fc32e7f2cc88c9dec934e509062953e.
/// The ordering variants keep upstream's operand order: upstream evaluates
/// `dep_value OP dependent_value` (the configured threshold on the left),
/// so `Greater` renders when the current field value is LESS than the
/// configured bytes, not greater. Preserved for definition parity.
pub(all) enum Condition {
  Equal(String, Bytes)
  NotEqual(String, Bytes)
  OneOf(String, Array[Bytes])
  NotOneOf(String, Array[Bytes])
  Greater(String, Bytes)
  GreaterEqual(String, Bytes)
  Less(String, Bytes)
  LessEqual(String, Bytes)
}

///|
fn Condition::path(self : Condition) -> String {
  match self {
    Equal(path, _)
    | NotEqual(path, _)
    | OneOf(path, _)
    | NotOneOf(path, _)
    | Greater(path, _)
    | GreaterEqual(path, _)
    | Less(path, _)
    | LessEqual(path, _) => path
  }
}

///|
/// Python bytes comparison: lexicographic over unsigned byte values.
fn bytes_lexicographic(left : Bytes, right : Bytes) -> Int {
  let shared = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i in 0..<shared {
    let x = left[i]
    let y = right[i]
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

///|
pub fn Block::when(self : Block, condition : Condition) -> Block {
  let saved = match condition {
    OneOf(path, values) => OneOf(path, values.copy())
    NotOneOf(path, values) => NotOneOf(path, values.copy())
    other => other
  }
  { ..self, condition: Some(saved), }
}

///|
fn CompiledRequest::is_visible(
  self : CompiledRequest,
  index : Int,
  replacements : Replacements,
  vars : Map[String, Bytes]?,
) -> Bool raise ModelError {
  for current = Some(index)
      current is Some(i)
      current = self.entries[i].parent {
    if self.entries[i].condition is Some(condition) {
      let target = self.resolve(condition.path())
      let value = match replacements.lookup(target) {
        Some(value) => value
        None =>
          match self.entries[target].kind {
            Atom(field) => field.value
            Dynamic(field, variable) =>
              match vars {
                Some(map) =>
                  match map.get(variable) {
                    Some(bytes) => bytes
                    None =>
                      raise Invalid("missing session variable: " + variable)
                  }
                None => field.value
              }
            _ => raise Invalid("condition target must be a field")
          }
      }
      let matches = match condition {
        Equal(_, expected) => value == expected
        NotEqual(_, expected) => value != expected
        OneOf(_, expected) => expected.contains(value)
        NotOneOf(_, expected) => !expected.contains(value)
        Greater(_, expected) => bytes_lexicographic(expected, value) > 0
        GreaterEqual(_, expected) => bytes_lexicographic(expected, value) >= 0
        Less(_, expected) => bytes_lexicographic(expected, value) < 0
        LessEqual(_, expected) => bytes_lexicographic(expected, value) <= 0
      }
      if !matches {
        return false
      }
    }
  }
  true
}
