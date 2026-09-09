///|
test "request stream does not call later mutation generators" {
  let called = Ref(0)
  let field : Field = {
    value: b"A",
    count: 1000000,
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
