///|
test "deterministic single-field stream resumes with identical identities" {
  let old = @moon_boofuzz.Request::new([
    Choice(b"A", [b"1", b"2"]),
    Static(b":"),
    Choice(b"B", [b"3", b"3"]),
  ])
  let request = @moon_boofuzz.CompiledRequest::from_request("r", old)
  let all = request.cases()
  let cases : Array[@moon_boofuzz.MutationCase] = []
  while all.next() is Some(case) {
    cases.push(case)
  }
  assert_eq(cases.map(case => case.payload), old.mutations())
  assert_eq(all.state(), Exhausted)
  let first = request.cases(limit=2)
  assert_eq(first.next(), Some(cases[0]))
  assert_eq(first.next(), Some(cases[1]))
  assert_eq(first.next(), None)
  assert_eq(first.state(), Limited)
  let rest = request.cases(start=first.position())
  assert_eq(rest.next(), Some(cases[2]))
  assert_eq(rest.next(), Some(cases[3]))
  assert_eq(rest.next(), None)
  assert_eq(request.cases(start=100).next(), None)
}

///|
test "stop and zero limit avoid rendering oversized later candidates" {
  let field = @moon_boofuzz.Field::simple(b"A", [b"B", b"too large"])
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [Leaf("x", field)]),
    max_bytes=1,
  )
  let stream = request.cases()
  assert_true(stream.next() is Some(_))
  stream.stop()
  assert_eq(stream.next(), None)
  assert_eq(stream.state(), Stopped)
  let zero = request.cases(limit=0)
  assert_eq(zero.next(), None)
  assert_eq(zero.state(), Limited)
  let overflow = request.cases(start=1)
  assert_true(
    try {
      ignore(overflow.next())
      false
    } catch {
      @moon_boofuzz.ModelError::Limit(_) => true
      _ => false
    },
  )
  assert_eq(overflow.state(), Stopped)
}
