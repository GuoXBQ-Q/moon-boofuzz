///|
test "request stream does not call later mutation generators" {
  let called = Ref(0)
  let field : Field = {
    value: b"A",
    count: 1000000,
    candidate_length: _ => 1L,
    candidate: fn(_) {
      called.val += 1
      b"B"
    },
  }
  let request = CompiledRequest::compile(Block::new("r", [Leaf("x", field)]))
  let stream = request.cases(start=999000, limit=2)
  assert_eq(called.val, 0)
  ignore(stream.next())
  ignore(stream.next())
  assert_eq(stream.next(), None)
  assert_eq(called.val, 2)
}

///|
test "oversized candidates are rejected before generator allocation" {
  let called = Ref(0)
  let field : Field = {
    value: b"A",
    count: 1,
    candidate_length: _ => 2147483647L,
    candidate: _ => {
      called.val += 1
      b"B"
    },
  }
  let request = CompiledRequest::compile(
    Block::new("r", [Leaf("x", field)]),
    max_bytes=16,
  )
  assert_true(
    try {
      ignore(request.cases().next())
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
  assert_eq(called.val, 0)
  let bytes = Field::binary(b"A", size=2147483647)
  let padded = CompiledRequest::compile(Block::new("r", [Leaf("x", bytes)]))
  assert_true(
    try {
      ignore(padded.cases().next())
      false
    } catch {
      Limit(_) => true
      _ => false
    },
  )
}
