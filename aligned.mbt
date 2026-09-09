///|
/// Upstream intentionally appends a full modulus even when already aligned.
pub fn Block::aligned(
  self : Block,
  modulus : Int,
  pattern? : Bytes = b"\x00",
) -> Block raise ModelError {
  guard modulus > 0 && !pattern.is_empty() else {
    raise Invalid("alignment requires positive modulus and nonempty pattern")
  }
  { ..self, alignment: Some((modulus, pattern)), }
}
