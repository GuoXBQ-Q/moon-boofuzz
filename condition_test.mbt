///|
test "conditions observe current mutation and render hidden blocks empty" {
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
  // Upstream still emits a test case per candidate; the hidden block
  // contributes empty bytes (boofuzz/blocks/block.py encode, 518c139).
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

///|
test "ordering conditions keep upstream operand order" {
  // Upstream dep_compare=">" renders when dep_value > dependent_value
  // (block.py:105), i.e. when the field value is lexicographically less.
  let gated = @moon_boofuzz.Block::new("body", [
    Leaf("x", @moon_boofuzz.Field::simple(b"X", [])),
  ]).when(@moon_boofuzz.Condition::Greater("r.flag", b"\x02"))
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("flag", @moon_boofuzz.Field::simple(b"\x01", [b"\x02", b"\x03"])),
      Nested(gated),
    ]),
  )
  let stream = request.cases()
  // flag "\x02": value == threshold -> dep_value > value is false -> hidden.
  assert_eq(stream.next().map(case => case.payload), Some(b"\x02"))
  // flag "\x03": value > threshold -> hidden.
  assert_eq(stream.next().map(case => case.payload), Some(b"\x03"))
  assert_eq(stream.next(), None)
  let visible = @moon_boofuzz.Block::new("body2", [
    Leaf("x", @moon_boofuzz.Field::simple(b"X", [])),
  ]).when(@moon_boofuzz.Condition::Greater("r.flag", b"\x04"))
  let request2 = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("flag", @moon_boofuzz.Field::simple(b"\x05", [])),
      Nested(visible),
    ]),
  )
  // threshold "\x04" > value "\x05"? No: 0x04 < 0x05 -> hidden.
  assert_eq(request2.render(), b"\x05")
  let visible2 = @moon_boofuzz.Block::new("body3", [
    Leaf("x", @moon_boofuzz.Field::simple(b"X", [])),
  ]).when(@moon_boofuzz.Condition::Greater("r.flag", b"\x06"))
  let request3 = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("flag", @moon_boofuzz.Field::simple(b"\x05", [])),
      Nested(visible2),
    ]),
  )
  // threshold "\x06" > value "\x05" -> visible.
  assert_eq(request3.render(), b"\x05X")
  let excluded = @moon_boofuzz.Block::new("body4", [
    Leaf("x", @moon_boofuzz.Field::simple(b"X", [])),
  ]).when(@moon_boofuzz.Condition::NotOneOf("r.flag", [b"\x05"]))
  let request4 = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("flag", @moon_boofuzz.Field::simple(b"\x05", [])),
      Nested(excluded),
    ]),
  )
  assert_eq(request4.render(), b"\x05")
}
