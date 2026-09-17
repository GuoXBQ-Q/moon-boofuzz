///|
test "JSON fields render the same bytes as API construction" {
  let source : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "r",
        "children": [
          { "type": "static", "name": "a", "value_hex": "00ff" },
          {
            "type": "integer",
            "name": "n",
            "value": "18446744073709551615",
            "width": 64,
            "endian": "big",
            "fuzzable": false,
          },
          { "type": "group", "name": "g", "values_hex": ["41", "42", "41"] },
          {
            "type": "bytes",
            "name": "b",
            "value_hex": "ff00",
            "size": 3,
            "fuzzable": false,
          },
          { "type": "text", "name": "s", "value": "协", "fuzzable": false },
          { "type": "delimiter", "name": "d", "value": ":", "fuzzable": false },
        ],
      },
    ],
  }
  let protocol = ProtocolDefinition::parse(source.stringify())
  let expected = @core.CompiledRequest::compile(
    @core.Block::new("r", [
      Leaf("a", @core.Field::simple(b"\x00\xff", [])),
      Leaf(
        "n",
        @core.Field::integer(
          0xffffffffffffffffUL,
          width=64,
          endian=Big,
          fuzzable=false,
        ),
      ),
      Leaf("g", @core.Field::group([b"A", b"B", b"A"])),
      Leaf("b", @core.Field::binary(b"\xff\x00", size=3, fuzzable=false)),
      Leaf("s", @core.Field::text("协", fuzzable=false)),
      Leaf("d", @core.Field::delimiter(":", fuzzable=false)),
    ]),
  )
  assert_eq(protocol.requests()[0].render(), expected.render())
  let generated : Array[Bytes] = []
  ignore(
    protocol.generate(case => {
      generated.push(case.case.payload)
      true
    }),
  )
  let stream = expected.cases()
  assert_eq(generated, [
    stream.next().unwrap().payload,
    stream.next().unwrap().payload,
  ])
}

///|
test "JSON nested computed and conditional blocks match API" {
  let source : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "r",
        "children": [
          {
            "type": "simple",
            "name": "flag",
            "value_hex": "30",
            "values_hex": ["31"],
          },
          { "type": "size", "name": "len", "target": "r.body", "length": 1 },
          { "type": "crc32", "name": "crc", "target": "r.body" },
          {
            "type": "block",
            "name": "body",
            "condition": { "field": "r.flag", "op": "eq", "value_hex": "31" },
            "alignment": { "modulus": 4 },
            "children": [{ "type": "static", "name": "x", "value_hex": "41" }],
          },
          {
            "type": "repeat",
            "name": "rep",
            "target": "r.body",
            "min": 0,
            "max": 1,
          },
        ],
      },
    ],
  }
  let protocol = ProtocolDefinition::parse(source.stringify())
  let body = @core.Block::new("body", [Leaf("x", @core.Field::simple(b"A", []))])
    .when(Equal("r.flag", b"1"))
    .aligned(4)
  let expected = @core.CompiledRequest::compile(
    @core.Block::new("r", [
      Leaf("flag", @core.Field::simple(b"0", [b"1"])),
      @core.Node::size("len", "r.body", length=1),
      @core.Node::checksum("crc", "r.body"),
      Nested(body),
      @core.Node::repeat("rep", "r.body", max=1),
    ]),
  )
  assert_eq(protocol.requests()[0].render(), expected.render())
  let stream = expected.cases()
  ignore(
    protocol.generate(case => {
      assert_eq(case.case.payload, stream.next().unwrap().payload)
      true
    }),
  )
  assert_true(stream.next() is None)
}

///|
test "definition limits resume and unsupported options fail" {
  let source : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "r",
        "children": [
          { "type": "simple", "name": "x", "values_hex": ["41", "42", "43"] },
        ],
      },
    ],
  }
  let protocol = ProtocolDefinition::parse(source.stringify())
  let result = protocol.generate(
    case => {
      assert_eq(case.case.payload, b"B")
      true
    },
    start=1,
    limit=1,
  )
  assert_eq(result.generated, 1)
  assert_eq(result.state, Limited)
  assert_true(
    try {
      ignore(decimal_u64("18446744073709551616"))
      false
    } catch {
      _ => true
    },
  )
  for
    invalid in [
      "{\"schema_version\":2,\"requests\":[]}", "{\"schema_version\":1,\"requests\":[],\"tls\":true}",
      "{\"schema_version\":1,\"requests\":[{\"name\":\"r\",\"children\":[{\"type\":\"text\",\"name\":\"x\",\"encoding\":\"utf16\"}]}]}",
      "{\"schema_version\":1,\"requests\":[{\"name\":\"r\",\"children\":[]}],\"edges\":[[\"r\",\"r\"]]}",
    ] {
    assert_true(
      try {
        ignore(ProtocolDefinition::parse(invalid))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "case_id_at verifies id resolution and group ids are rejected" {
  let source : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "a",
        "children": [
          { "type": "simple", "name": "x", "values_hex": ["41", "42"] },
        ],
      },
      {
        "name": "b",
        "children": [
          { "type": "simple", "name": "y", "values_hex": ["43", "44"] },
        ],
      },
    ],
  }
  let protocol = ProtocolDefinition::parse(source.stringify())
  // Global positions walk across paths in definition order.
  assert_eq(protocol.case_id_at(0), Some("[\"a\"]/v1:a.x:0"))
  assert_eq(protocol.case_id_at(2), Some("[\"b\"]/v1:b.y:0"))
  assert_eq(protocol.case_id_at(4), None)
  // The id of the case at a resolved position matches the id itself.
  // position_of_id takes the inner id; case_id_at returns the full id.
  let offset = protocol.position_of_id("v1:b.y:1")
  assert_eq(protocol.case_id_at(offset), Some("[\"b\"]/v1:b.y:1"))
  // Group product ids carry a '+' part and are rejected explicitly.
  assert_true(
    try {
      ignore(protocol.position_of_id("v1:a.g:0+a.x:0"))
      false
    } catch {
      _ => true
    },
  )
}
