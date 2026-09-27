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
  // The oversized candidate at index 1 is skipped without rendering, so
  // the stream ends cleanly instead of aborting.
  assert_eq(overflow.next(), None)
  assert_eq(overflow.state(), Exhausted)
}

///|
test "oversized gaps preserve raw ordinals and resumable positions" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("x", @moon_boofuzz.Field::simple(b"A", [b"AAA", b"B", b"CCC", b"C"])),
    ]),
    max_bytes=2,
  )
  let first = request.cases(limit=1)
  let case = first.next().unwrap()
  assert_eq(case.ordinal, 1)
  assert_eq(case.mutation_index, 1)
  assert_eq(first.position(), 2)
  assert_eq(first.next(), None)
  assert_eq(first.state(), Limited)
  let rest = request.cases(start=first.position())
  let next = rest.next().unwrap()
  assert_eq(next.ordinal, 3)
  assert_eq(next.mutation_index, 3)
  assert_eq(next.payload, b"C")
  assert_eq(rest.next(), None)
  assert_eq(rest.position(), 4)
}

///|
test "sequential and combinatorial resumes preserve cases after oversized renders" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("x", @moon_boofuzz.Field::simple(b"A", [b"AAA", b"B"])),
      Leaf("y", @moon_boofuzz.Field::simple(b"A", [b"CCC", b"D"])),
    ]),
    max_bytes=2,
  )
  for combinatorial in [false, true] {
    let stream = if combinatorial {
      request.combinatorial_cases(max_depth=2)
    } else {
      request.cases()
    }
    let first = stream.next().unwrap()
    assert_eq(first.ordinal, 1)
    let position = stream.position()
    let expected : Array[@moon_boofuzz.MutationCase] = []
    while stream.next() is Some(case) {
      expected.push(case)
    }
    assert_true(!expected.is_empty())
    let resumed = if combinatorial {
      request.combinatorial_cases(start=position, max_depth=2)
    } else {
      request.cases(start=position)
    }
    let actual : Array[@moon_boofuzz.MutationCase] = []
    while resumed.next() is Some(case) {
      actual.push(case)
    }
    assert_eq(actual, expected)
  }
}
