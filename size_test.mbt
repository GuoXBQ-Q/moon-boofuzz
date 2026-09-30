///|
test "size follows payload mutations and explicit malformed lengths" {
  let size = @moon_boofuzz.Node::size(
    "len",
    "r.body",
    length=2,
    endian=Big,
    offset=1,
    inclusive=true,
    mutations=[0UL],
  )
  let body = @moon_boofuzz.Block::new("body", [
    Leaf("x", @moon_boofuzz.Field::simple(b"AB", [b"CDE"])),
  ])
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [size, Nested(body)]),
  )
  assert_eq(request.render(), b"\x00\x05AB")
  let stream = request.cases()
  assert_eq(stream.next().map(case => case.payload), Some(b"\x00\x00AB"))
  assert_eq(stream.next().map(case => case.payload), Some(b"\x00\x06CDE"))
}

///|
test "size of own parent includes fixed width and inclusive adds again" {
  for length in [1, 2, 4, 8] {
    let request = @moon_boofuzz.CompiledRequest::compile(
      @moon_boofuzz.Block::new("r", [
        @moon_boofuzz.Node::size("len", "r", length~),
        Leaf("data", @moon_boofuzz.Field::simple(b"ABC", [])),
      ]),
    )
    assert_eq(request.render()[0], (length + 3).to_byte())
    assert_eq(request.render().length(), length + 3)
  }
  let inclusive = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      @moon_boofuzz.Node::size("len", "r", length=1, inclusive=true),
    ]),
  )
  assert_eq(inclusive.render(), b"\x02")
}

///|
test "size rejects negative lengths overflow unknown references and ordinary cycles" {
  for
    size in [
      @moon_boofuzz.Node::size("len", "r.body", length=1, offset=-1),
      @moon_boofuzz.Node::size("len", "missing"),
    ] {
    assert_true(
      try {
        ignore(
          @moon_boofuzz.CompiledRequest::compile(
            @moon_boofuzz.Block::new("r", [
              size,
              Nested(@moon_boofuzz.Block::new("body", [])),
            ]),
          ),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let large = @moon_boofuzz.Block::new("r", [
    @moon_boofuzz.Node::size("len", "r", length=1),
    Leaf("data", @moon_boofuzz.Field::simple(b"A".repeat(255), [])),
  ])
  assert_true(
    try {
      ignore(@moon_boofuzz.CompiledRequest::compile(large))
      false
    } catch {
      _ => true
    },
  )
  let a = @moon_boofuzz.Block::new("a", [@moon_boofuzz.Node::size("len", "r.b")])
  let b = @moon_boofuzz.Block::new("b", [@moon_boofuzz.Node::size("len", "r.a")])
  assert_true(
    try {
      ignore(
        @moon_boofuzz.CompiledRequest::compile(
          @moon_boofuzz.Block::new("r", [Nested(a), Nested(b)]),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "ascii size renders the live body length as decimal text" {
  // The HTTP Content-Length shape (upstream http_with_body.py): a text
  // length field tracking its body block.
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("label", @moon_boofuzz.Field::simple(b"CL:", [], fuzzable=false)),
      @moon_boofuzz.Node::size("len", "r.body", ascii=true, fuzzable=false),
      Nested(
        @moon_boofuzz.Block::new("body", [
          Leaf("x", @moon_boofuzz.Field::simple(b"AB", [b"", b"CDEF"])),
        ]),
      ),
    ]),
  )
  assert_eq(request.render(), b"CL:2AB")
  let stream = request.cases()
  // Body mutations change the wire length and the text length follows.
  assert_eq(stream.next().map(case => case.payload), Some(b"CL:0"))
  assert_eq(stream.next().map(case => case.payload), Some(b"CL:4CDEF"))
}

///|
test "ascii size boundary mutations render as decimal text" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      @moon_boofuzz.Node::size("len", "r.body", length=1, ascii=true, mutations=[
        0UL, 255UL,
      ]),
      Nested(
        @moon_boofuzz.Block::new("body", [
          Leaf("x", @moon_boofuzz.Field::simple(b"AB", [])),
        ]),
      ),
    ]),
  )
  assert_eq(request.render(), b"2AB")
  let stream = request.cases()
  assert_eq(stream.next().map(case => case.payload), Some(b"0AB"))
  assert_eq(stream.next().map(case => case.payload), Some(b"255AB"))
}

///|
test "ascii size rejects inclusive and self-containment" {
  // inclusive is rejected at construction time.
  assert_true(
    try {
      ignore(
        @moon_boofuzz.Node::size("len", "r.body", ascii=true, inclusive=true),
      )
      false
    } catch {
      _ => true
    },
  )
  // Containing the ascii size in its own target is rejected at compile.
  assert_true(
    try {
      ignore(
        @moon_boofuzz.CompiledRequest::compile(
          @moon_boofuzz.Block::new("r", [
            @moon_boofuzz.Node::size("len", "r", ascii=true),
            Nested(@moon_boofuzz.Block::new("body", [])),
          ]),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}
