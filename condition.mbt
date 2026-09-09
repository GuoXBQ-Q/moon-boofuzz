///|
pub(all) enum Condition {
  Equal(String, Bytes)
  NotEqual(String, Bytes)
  OneOf(String, Array[Bytes])
}

///|
fn Condition::path(self : Condition) -> String {
  match self {
    Equal(path, _) | NotEqual(path, _) | OneOf(path, _) => path
  }
}

///|
pub fn Block::when(self : Block, condition : Condition) -> Block {
  let saved = match condition {
    OneOf(path, values) => OneOf(path, values.copy())
    other => other
  }
  { ..self, condition: Some(saved), }
}

///|
fn CompiledRequest::is_visible(
  self : CompiledRequest,
  index : Int,
  replacement : (Int, Bytes)?,
) -> Bool raise ModelError {
  for current = Some(index)
      current is Some(i)
      current = self.entries[i].parent {
    if self.entries[i].condition is Some(condition) {
      let target = self.resolve(condition.path())
      let value = if replacement is Some((id, value)) && id == target {
        value
      } else {
        match self.entries[target].kind {
          Atom(field) => field.value
          _ => raise Invalid("condition target must be a field")
        }
      }
      let matches = match condition {
        Equal(_, expected) => value == expected
        NotEqual(_, expected) => value != expected
        OneOf(_, expected) => expected.contains(value)
      }
      if !matches {
        return false
      }
    }
  }
  true
}
