///|
test "alignment empty exact and multi byte pattern" {
  for
    pair in [
      (b"", b"ABAB"),
      (b"1234", b"1234ABAB"),
      (b"12", b"12AB"),
      (b"1", b"1ABA"),
    ] {
    let (input, expected) = pair
    let block = @moon_boofuzz.Block::new("r", [
      Leaf("x", @moon_boofuzz.Field::simple(input, [])),
    ]).aligned(4, pattern=b"AB")
    assert_eq(@moon_boofuzz.CompiledRequest::compile(block).render(), expected)
  }
  assert_true(
    try {
      ignore(@moon_boofuzz.Block::new("r", []).aligned(0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moon_boofuzz.Block::new("r", []).aligned(4, pattern=b""))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @moon_boofuzz.CompiledRequest::compile(
          @moon_boofuzz.Block::new("r", []).aligned(4),
          max_bytes=3,
        ),
      )
      false
    } catch {
      @moon_boofuzz.ModelError::Limit(_) => true
      _ => false
    },
  )
}
