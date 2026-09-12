///|
fn accept_bytes(listener : FixtureSocket) -> Bytes raise {
  let peer = fixture_new()
  defer fixture_close(peer)
  assert_eq(fixture_wait(listener, 0, 1000), 1)
  assert_eq(fixture_accept(listener, peer), 0)
  let bytes : Array[Byte] = []
  let buffer = FixedArray::make(256, b'\x00')
  for ;; {
    assert_eq(fixture_wait(peer, 0, 1000), 1)
    let n = fixture_receive(peer, buffer, 256)
    assert_true(n >= 0)
    if n == 0 {
      break
    }
    for i in 0..<n {
      bytes.push(buffer[i])
    }
  }
  Bytes::from_array(bytes)
}

///|
fn parse_ping(bytes : Bytes) -> Bool {
  guard bytes.has_prefix(b"PING ") else { return false }
  let value = @utf8.decode(bytes[5:]) catch { _ => return false }
  !value.is_empty() && value.length() <= 4
}

///|
test "report preserves a valid prefix and replay rejects an incomplete tail before connecting" {
  let server = fixture_new()
  defer fixture_close(server)
  let port = fixture_listen(server)
  let path = fixture_path()
  defer fixture_remove(path)
  let writer = @recordio.Writer::open(@utf8.decode(path))
  let record : @records.CaseRecord = {
    format_version: 1,
    case_id: "saved",
    generator_version: "v1",
    request_name: "r",
    field_path: "r.x",
    mutation_index: 0,
    ordinal: 0,
    path: ["r"],
    config: {
      "transport": "tcp",
      "endpoint": { "host": "127.0.0.1", "port": port },
    },
    steps: [{ request_name: "r", sent: b"A", received: b"", completed: false, }],
    outcome: "receive_timeout",
    detail: "timeout",
    failed_step: Some(0),
  }
  writer.append(record)
  writer.close()
  let file = fixture_open(path, 1)
  assert_eq(fixture_write(file, b"{", 1), 0)
  fixture_file_close(file)
  assert_eq(dispatch(["report", @utf8.decode(path)]), 2)
  assert_true(
    try {
      ignore(dispatch(["replay", @utf8.decode(path), "--id", "saved"]))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(fixture_wait(server, 0, 10), 0)
}

///|
test "offline parser consumes generated binary cases without text corruption" {
  let value : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "r",
        "children": [
          { "type": "static", "name": "prefix", "value_hex": "50494e4720" },
          {
            "type": "simple",
            "name": "x",
            "values_hex": ["", "00ff", "6c6f6e67"],
          },
        ],
      },
    ],
  }
  let definition = @definition.ProtocolDefinition::parse(value.stringify())
  let accepted : Array[Bool] = []
  let result = definition.generate(case => {
    accepted.push(parse_ping(case.case.payload))
    true
  })
  assert_eq(result.generated, 3)
  assert_eq(accepted, [false, false, true])
}

///|
test "TCP robustness run reports and replays a failed request from saved bytes" {
  let server = fixture_new()
  defer fixture_close(server)
  let port = fixture_listen(server)
  let definition_path = fixture_path()
  defer fixture_remove(definition_path)
  let output_path = fixture_path()
  defer fixture_remove(output_path)
  save_definition(definition_path, {
    "schema_version": 1,
    "requests": [
      {
        "name": "r",
        "children": [{ "type": "simple", "name": "x", "values_hex": ["00ff"] }],
      },
    ],
    "execution": {
      "transport": "tcp",
      "endpoint": {
        "host": "127.0.0.1",
        "port": port,
        "receive_timeout_ms": 20,
      },
      "policies": { "r": { "kind": "fixed", "length": 1 } },
      "case_limit": 1,
    },
  })
  assert_eq(
    dispatch([
      "run",
      @utf8.decode(definition_path),
      "--output",
      @utf8.decode(output_path),
    ]),
    0,
  )
  let read = @recordio.read_records(@utf8.decode(output_path))
  assert_true(read.error is None)
  assert_eq(read.records[0].outcome, "receive_timeout")
  assert_eq(read.records[0].steps[0].sent, b"\x00\xff")
  assert_eq(accept_bytes(server), b"\x00\xff")
  assert_eq(dispatch(["report", @utf8.decode(output_path)]), 0)
  fixture_remove(definition_path)
  assert_eq(
    dispatch([
      "replay",
      @utf8.decode(output_path),
      "--id",
      read.records[0].case_id,
    ]),
    1,
  )
  assert_eq(accept_bytes(server), b"\x00\xff")
}

///|
test "stateful CLI repeats handshake and authentication for every target case" {
  let server = fixture_new()
  defer fixture_close(server)
  let port = fixture_listen(server)
  let input_path = fixture_path()
  defer fixture_remove(input_path)
  let output_path = fixture_path()
  defer fixture_remove(output_path)
  save_definition(input_path, {
    "schema_version": 1,
    "requests": [
      {
        "name": "hello",
        "children": [
          { "type": "static", "name": "x", "value_hex": "48454c4c4f0a" },
        ],
      },
      {
        "name": "auth",
        "children": [
          { "type": "static", "name": "x", "value_hex": "4155544820746573740a" },
        ],
      },
      {
        "name": "query",
        "children": [
          {
            "type": "simple",
            "name": "x",
            "values_hex": ["44415441206f6e650a", "444154412074776f0a"],
          },
        ],
      },
    ],
    "edges": [["hello", "auth"], ["auth", "query"]],
    "targets": ["query"],
    "execution": {
      "transport": "tcp",
      "endpoint": { "host": "127.0.0.1", "port": port },
      "case_limit": 2,
    },
  })
  assert_eq(
    dispatch([
      "run",
      @utf8.decode(input_path),
      "--output",
      @utf8.decode(output_path),
    ]),
    0,
  )
  assert_eq(accept_bytes(server), b"HELLO\nAUTH test\nDATA one\n")
  assert_eq(accept_bytes(server), b"HELLO\nAUTH test\nDATA two\n")
  let read = @recordio.read_records(@utf8.decode(output_path))
  assert_eq(read.records.length(), 2)
  for record in read.records {
    assert_eq(record.path, ["hello", "auth", "query"])
    assert_eq(record.steps.length(), 3)
  }
  assert_eq(dispatch(["report", @utf8.decode(output_path)]), 0)
}
