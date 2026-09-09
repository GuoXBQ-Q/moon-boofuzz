///|
test "conditions observe current mutation and skip hidden internal cases" {
  let body = @moon_boofuzz.Block::new("body", [
    Leaf("data", @moon_boofuzz.Field::simple(b"X", [b"Y"])),
  ]).when(Equal("r.flag", b"1"))
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("flag", @moon_boofuzz.Field::simple(b"0", [b"1", b"0"])),
      Nested(body),
    ]),
  )
  assert_eq(request.render(), b"0")
  let stream = request.cases()
  assert_eq(stream.next().map(case => case.payload), Some(b"1X"))
  assert_eq(stream.next().map(case => case.payload), Some(b"0"))
  assert_eq(stream.next(), None)
  assert_eq(stream.state(), Exhausted)
  assert_eq(request.render_path("r.body.data"), b"")
}

///|
test "set conditions snapshot values and unequal condition renders" {
  let allowed = [b"A", b"B"]
  let body = @moon_boofuzz.Block::new("body", [
    Leaf("x", @moon_boofuzz.Field::simple(b"X", [])),
  ]).when(OneOf("r.flag", allowed))
  allowed.clear()
  let unequal = @moon_boofuzz.Block::new("other", [
    Leaf("x", @moon_boofuzz.Field::simple(b"Y", [])),
  ]).when(NotEqual("r.flag", b"B"))
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("flag", @moon_boofuzz.Field::simple(b"A", [])),
      Nested(body),
      Nested(unequal),
    ]),
  )
  assert_eq(request.render(), b"AXY")
  let bad = @moon_boofuzz.Block::new("r", []).when(Equal("unknown", b""))
  assert_true(
    try {
      ignore(@moon_boofuzz.CompiledRequest::compile(bad))
      false
    } catch {
      _ => true
    },
  )
}
