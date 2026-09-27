///|
test "repeat default and inclusive stepped sequence" {
  let block = @moon_boofuzz.Block::new("item", [
    Leaf("x", @moon_boofuzz.Field::simple(b"AB", [])),
  ])
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Nested(block),
      @moon_boofuzz.Node::repeat("copies", "r.item", min=0, max=4, step=2),
    ]),
  )
  assert_eq(request.render(), b"AB")
  let stream = request.cases()
  for expected in [b"AB", b"ABABAB", b"ABABABABAB"] {
    assert_eq(stream.next().map(case => case.payload), Some(expected))
  }
  assert_eq(stream.next(), None)
}

///|
test "repeat rejects invalid parameters references and oversized payloads" {
  let block = @moon_boofuzz.Block::new("item", [
    Leaf("x", @moon_boofuzz.Field::simple(b"AB", [])),
  ])
  for
    node in [
      @moon_boofuzz.Node::repeat("copies", "r.item", step=0),
      @moon_boofuzz.Node::repeat("copies", "r.item", min=2, max=1),
      @moon_boofuzz.Node::repeat("copies", "r.missing"),
      @moon_boofuzz.Node::repeat("copies", "r"),
    ] {
    assert_true(
      try {
        ignore(
          @moon_boofuzz.CompiledRequest::compile(
            @moon_boofuzz.Block::new("r", [Nested(block), node]),
          ),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Nested(block),
      @moon_boofuzz.Node::repeat("copies", "r.item", min=2, max=2),
    ]),
    max_bytes=5,
  )
  // Every repeat render exceeds the byte budget, so all candidates are
  // skipped and the stream ends cleanly instead of aborting.
  assert_eq(request.cases().next(), None)
}
