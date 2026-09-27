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
test "oversized candidates are skipped before generator allocation" {
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
  // The stream skips the impossible case instead of aborting, and the
  // candidate generator is never invoked.
  assert_eq(request.cases().next(), None)
  assert_eq(called.val, 0)
  let bytes = Field::binary(b"A", size=2147483647)
  let padded = CompiledRequest::compile(Block::new("r", [Leaf("x", bytes)]))
  assert_eq(padded.cases().next(), None)
}

///|
test "oversized candidate does not hide later fields" {
  let oversized : Field = {
    value: b"A",
    count: 1,
    candidate_length: _ => 2147483647L,
    candidate: _ => b"B",
  }
  let normal : Field = {
    value: b"A",
    count: 2,
    candidate_length: _ => 1L,
    candidate: i => if i == 0 { b"B" } else { b"C" },
  }
  let request = CompiledRequest::compile(
    Block::new("r", [Leaf("x", oversized), Leaf("y", normal)]),
    max_bytes=16,
  )
  let stream = request.cases()
  let first = match stream.next() {
    Some(case) => case
    None => fail("expected the second field's first mutation")
  }
  inspect(first.field_path, content="r.y")
  inspect(first.mutation_index, content="0")
  let second = match stream.next() {
    Some(case) => case
    None => fail("expected the second field's second mutation")
  }
  inspect(second.field_path, content="r.y")
  inspect(second.mutation_index, content="1")
  assert_eq(stream.next(), None)
}
