// Differential tests against the upstream Python oracle
// (boofuzz 518c13904fc32e7f2cc88c9dec934e509062953e), probed with
// scripts/oracle.mbtx. Python is a development oracle only.

///|
test "upstream size delegates mutations to the inner bit field" {
  // Oracle: Size(name='len', block_name='body', length=2) reports 140
  // mutations; the boundary integers 0..3 ... 65534, 65535 render through
  // the size encoding and bypass length computation.
  let field = request_fixture(
    @moon_boofuzz.CompiledRequest::compile(
      @moon_boofuzz.Block::new("r", [
        @moon_boofuzz.Node::size("len", "r.body", length=2),
        Nested(
          @moon_boofuzz.Block::new("body", [
            Leaf("x", @moon_boofuzz.Field::simple(b"AB", [])),
          ]),
        ),
      ]),
    ),
  )
  assert_eq(field.num_mutations(), 140)
  assert_eq(field.mutation(0), Some(b"\x00\x00AB"))
  assert_eq(field.mutation(3), Some(b"\x03\x00AB"))
  assert_eq(field.mutation(139), Some(b"\xff\xffAB"))
}

///|
test "upstream checksum auto mutations are six byte boundaries" {
  // Oracle: Checksum(name='crc', block_name='body') yields
  // 00000000, 11111111, eeeeeeee, ffffffff, fffffffe, 00000001.
  let field = request_fixture(
    @moon_boofuzz.CompiledRequest::compile(
      @moon_boofuzz.Block::new("r", [
        @moon_boofuzz.Node::checksum("crc", "r.body"),
        Nested(
          @moon_boofuzz.Block::new("body", [
            Leaf("x", @moon_boofuzz.Field::simple(b"AB", [])),
          ]),
        ),
      ]),
    ),
  )
  assert_eq(field.num_mutations(), 6)
  assert_eq(field.mutation(0), Some(b"\x00\x00\x00\x00AB"))
  assert_eq(field.mutation(1), Some(b"\x11\x11\x11\x11AB"))
  assert_eq(field.mutation(2), Some(b"\xee\xee\xee\xeeAB"))
  assert_eq(field.mutation(3), Some(b"\xff\xff\xff\xffAB"))
  assert_eq(field.mutation(4), Some(b"\xff\xff\xff\xfeAB"))
  assert_eq(field.mutation(5), Some(b"\x00\x00\x00\x01AB"))
}

///|
test "upstream random data draws the deterministic Random(0) stream" {
  // Oracle: RandomData(default_value=b'R', min_length=0, max_length=6,
  // max_mutations=8) yields:
  // c5d71484f8cf, 9bf4b76f4790, 30, 804b9e32, 25a9f133b5, a168f4, 851f07, ''.
  let field = @moon_boofuzz.Field::random_data(
    default_value=b"R",
    min_length=0,
    max_length=6,
    max_mutations=8,
  )
  assert_eq(field.default_value(), b"R")
  assert_eq(field.num_mutations(), 8)
  let expected : Array[Bytes] = [
    b"\xc5\xd7\x14\x84\xf8\xcf", b"\x9b\xf4\xb7\x6f\x47\x90", b"\x30", b"\x80\x4b\x9e\x32",
    b"\x25\xa9\xf1\x33\xb5", b"\xa1\x68\xf4", b"\x85\x1f\x07", b"",
  ]
  for i, value in expected {
    assert_eq(field.mutation(i), Some(value))
  }
}

///|
test "upstream random data step mode fixes lengths without drawing" {
  let field = @moon_boofuzz.Field::random_data(
    min_length=1,
    max_length=5,
    step=2,
  )
  // Step mode: lengths 1, 3, 5 -> three candidates, deterministic content.
  assert_eq(field.num_mutations(), 3)
  assert_eq(field.mutation(0).map(value => value.length()), Some(1))
  assert_eq(field.mutation(1).map(value => value.length()), Some(3))
  assert_eq(field.mutation(2).map(value => value.length()), Some(5))
}

///|
test "upstream float formats the seeded uniform stream" {
  // Oracle: Float(default_value=0.0, seed=7) yields 999 formatted strings;
  // first six: 0.0, 32.4, 15.1, 65.1, 7.2, 53.6; last two: 5.4, 50.4.
  let field = @moon_boofuzz.Field::float(seed=7L)
  assert_eq(field.default_value(), b"0.0")
  assert_eq(field.num_mutations(), 999)
  assert_eq(field.mutation(0), Some(b"0.0"))
  assert_eq(field.mutation(1), Some(b"32.4"))
  assert_eq(field.mutation(2), Some(b"15.1"))
  assert_eq(field.mutation(3), Some(b"65.1"))
  assert_eq(field.mutation(4), Some(b"7.2"))
  assert_eq(field.mutation(5), Some(b"53.6"))
}

///|
test "upstream float encodes ieee 754 with the formatted value" {
  // Oracle: Float(default_value=1.5, s_format='.2f', seed=7,
  // encode_as_ieee_754=True, endian='little', max_mutations=6) yields:
  // 0000c03f, 1f850142, ae477141, 142e8242, 14aee740, 295c5642.
  let field = @moon_boofuzz.Field::float(
    default_value=1.5,
    s_format=".2f",
    seed=7L,
    max_mutations=6,
    encode_as_ieee_754=true,
    endian=Little,
  )
  assert_eq(field.default_value(), b"\x00\x00\xc0\x3f")
  let expected : Array[Bytes] = [
    b"\x00\x00\xc0\x3f", b"\x1f\x85\x01\x42", b"\xae\x47\x71\x41", b"\x14\x2e\x82\x42",
    b"\x14\xae\xe7\x40", b"\x29\x5c\x56\x42",
  ]
  assert_eq(field.num_mutations(), expected.length())
  for i, value in expected {
    assert_eq(field.mutation(i), Some(value))
  }
}

///|
test "from lines filters empty and oversized entries" {
  let field = @moon_boofuzz.Field::from_lines(
    lines=[b"alpha", b"", b"beta-toolong", b"gamma"],
    max_len=5,
  )
  // max_len filters by length; the filtered library keeps first occurrences.
  assert_eq(field.num_mutations(), 2)
  assert_eq(field.mutation(0), Some(b"alpha"))
  assert_eq(field.mutation(1), Some(b"gamma"))
}

///|
test "mirror renders the target's current value" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("data", @moon_boofuzz.Field::simple(b"AB", [b"CD"])),
      @moon_boofuzz.Node::mirror("echo", "r.data"),
    ]),
  )
  assert_eq(request.render(), b"ABAB")
  let stream = request.cases()
  assert_eq(stream.next().map(case => case.payload), Some(b"CDCD"))
  assert_eq(stream.next(), None)
  let sized = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r2", [
      Nested(
        @moon_boofuzz.Block::new("body", [
          Leaf("x", @moon_boofuzz.Field::simple(b"", [b"AB"])),
        ]),
      ),
      @moon_boofuzz.Node::size("len", "r2.body", length=1),
      @moon_boofuzz.Node::mirror("echo", "r2.len"),
    ]),
  )
  assert_eq(sized.render(), b"\x00\x00")
  ignore(sized)
}

///|
test "upstream group and block cartesian products" {
  // Oracle: Request([Group(op,[A,B]), Block(body, group='op'){x: Simple(1,[2,3])}])
  // yields 5 cases: plain op=B, plain x=2, plain x=3, then products B+2, B+3.
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("op", @moon_boofuzz.Field::group([b"A", b"B"])),
      Nested(
        @moon_boofuzz.Block::new("body", [
          Leaf("x", @moon_boofuzz.Field::simple(b"1", [b"2", b"3"])),
        ]).with_group("r.op"),
      ),
    ]),
  )
  assert_eq(request.render(), b"A1")
  let field = request_fixture(request)
  let expected : Array[Bytes] = [b"B1", b"A2", b"A3", b"B2", b"B3"]
  assert_eq(field.num_mutations(), expected.length())
  for i, value in expected {
    assert_eq(field.mutation(i), Some(value))
  }
  // Product identities carry both mutated fields.
  let stream = request.cases()
  let mut fourth : @moon_boofuzz.MutationCase? = None
  for _ in 0..<3 {
    ignore(stream.next())
  }
  fourth = stream.next()
  let case = fourth.unwrap()
  assert_eq(case.payload, b"B2")
  assert_eq(case.id, "v1:r.op:0+r.body.x:0")
  assert_eq(case.field_path, "r.body.x")
  assert_eq(case.extra, [("r.op", 0)])
  // Raw positions include the product replay.
  assert_eq(request.raw_mutation_count(), 5L)
}

///|
test "upstream combinatorial enumeration depth two" {
  // Oracle: Session._generate_mutations_indefinitely(max_depth=2) over
  // Request([Simple(a,1,[2,3]), Simple(b,4,[5])]) yields exactly:
  // [a=2], [a=3], [b=5], [a=2,b=5], [a=3,b=5].
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      Leaf("a", @moon_boofuzz.Field::simple(b"1", [b"2", b"3"])),
      Leaf("b", @moon_boofuzz.Field::simple(b"4", [b"5"])),
    ]),
  )
  let stream = request.combinatorial_cases(max_depth=2)
  let expected : Array[Bytes] = [b"24", b"34", b"15", b"25", b"35"]
  for value in expected {
    let case = stream.next().unwrap()
    assert_eq(case.payload, value)
  }
  assert_eq(stream.next(), None)
  assert_eq(stream.state(), Exhausted)
  // Depth 1 alone equals the sequential stream.
  let shallow = request.combinatorial_cases(max_depth=1)
  let mut count = 0
  while shallow.next() is Some(_) {
    count += 1
  }
  assert_eq(count, 3)
}

///|
test "adler32 and crc32c reference vectors" {
  // zlib.adler32(b'Wikipedia') == 0x11e60398
  assert_eq(@moon_boofuzz.adler32(b"Wikipedia"), 0x11e60398U)
  // Castagnoli CRC-32C reference: crc32c(b'123456789') == 0xe3069283
  assert_eq(@moon_boofuzz.crc32c(b"123456789"), 0xe3069283U)
  assert_eq(@moon_boofuzz.crc32c(b"hello"), 0x9a71bb4cU)
}
