///|
test "standard CRC32 vectors" {
  assert_eq(@moon_boofuzz.crc32(b""), 0U)
  assert_eq(@moon_boofuzz.crc32(b"123456789"), 0xcbf43926U)
}

///|
test "CRC32 recomputes and explicit values replace calculated checksum" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      @moon_boofuzz.Node::checksum("crc", "r.body", endian=Big, mutations=[0U]),
      Nested(
        @moon_boofuzz.Block::new("body", [
          Leaf("data", @moon_boofuzz.Field::simple(b"123456789", [b""])),
        ]),
      ),
    ]),
  )
  assert_eq(request.render(), b"\xcb\xf4\x39\x26123456789")
  let stream = request.cases()
  assert_eq(
    stream.next().map(case => case.payload),
    Some(b"\x00\x00\x00\x00123456789"),
  )
  assert_eq(stream.next().map(case => case.payload), Some(b"\x00\x00\x00\x00"))
}

///|
test "parent checksum zeros itself and combines with size" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      @moon_boofuzz.Node::size("len", "r", length=1),
      @moon_boofuzz.Node::checksum("crc", "r"),
      Leaf("x", @moon_boofuzz.Field::simple(b"A", [])),
    ]),
  )
  let crc = @moon_boofuzz.crc32(b"\x06\x00\x00\x00\x00A")
  assert_eq(
    request.render(),
    b"\x06" + Bytes::makei(4, i => ((crc >> (8 * i)) & 255U).to_byte()) + b"A",
  )
  let a = @moon_boofuzz.Block::new("a", [
    @moon_boofuzz.Node::checksum("crc", "r.b"),
  ])
  let b = @moon_boofuzz.Block::new("b", [
    @moon_boofuzz.Node::checksum("crc", "r.a"),
  ])
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
