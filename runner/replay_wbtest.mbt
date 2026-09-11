///|
test "replay sends saved bytes even when generator changes and accepts different replies" {
  let producer = Runner::with_dialer(
    runner_paths(),
    () => {
      {
        sent: [],
        responses: [@transport.Data(b"OKOLD")],
        fail_at: -1,
        last_sent: 0,
        closed: false,
      }
      as &Channel
    },
    policies={ "hello": Fixed(2), "query": Fixed(3) },
  )
  let saved = producer.record(producer.next().unwrap())
  let config_json : Json = {
    "transport": "tcp",
    "endpoint": { "host": "127.0.0.1", "port": 9000 },
    "policies": {
      "hello": { "kind": "fixed", "length": 2 },
      "query": { "kind": "fixed", "length": 3 },
    },
  }
  let record = { ..saved, config: config_json, }
  let changed = @core.Field::simple(b"QUERY", [b"new-generator"])
  assert_true(changed.mutation(0) != Some(record.steps[1].sent))
  let socket : Mock = {
    sent: [],
    responses: [@transport.Data(b"NONEW")],
    fail_at: -1,
    last_sent: 0,
    closed: false,
  }
  let replayed = replay_sequence(record, ExecutionConfig::parse(config_json), () => {
    socket as &Channel
  })
  assert_eq(socket.sent, [b"HELLO", b"one"])
  assert_eq(replayed.steps[1].received, b"NEW")
  assert_eq(replayed.outcome, Passed)
  assert_true(socket.closed)
}

///|
test "replay target override sends exact bytes to a new real TCP endpoint" {
  let listener = fixture_new()
  defer fixture_close(listener)
  let port = fixture_listen(listener)
  assert_true(port > 0)
  let producer = Runner::with_dialer(runner_paths(), () => {
    { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
    as &Channel
  })
  let saved = producer.record(producer.next().unwrap())
  let record = {
    ..saved,
    config: {
      "transport": "tcp",
      "endpoint": { "host": "127.0.0.1", "port": 1 },
    },
  }
  let result = replay(record, override_target=("127.0.0.1", port))
  assert_eq(result.outcome, Passed)
  assert_eq(result.case_id, saved.case_id)
  let accepted = fixture_new()
  defer fixture_close(accepted)
  assert_eq(fixture_wait(listener, 0, 1000), 1)
  assert_eq(fixture_accept(listener, accepted), 0)
  let bytes : Array[Byte] = []
  let buffer = FixedArray::make(128, b'\x00')
  for ;; {
    assert_eq(fixture_wait(accepted, 0, 1000), 1)
    let n = fixture_receive(accepted, buffer, 128)
    assert_true(n >= 0)
    if n == 0 {
      break
    }
    for i in 0..<n {
      bytes.push(buffer[i])
    }
  }
  assert_eq(Bytes::from_array(bytes), b"HELLOone")
}

///|
test "replay rejects unsupported config before connecting" {
  let producer = Runner::with_dialer(runner_paths(), () => {
    { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
    as &Channel
  })
  let record = producer.record(producer.next().unwrap())
  assert_true(
    try {
      ignore(replay(record))
      false
    } catch {
      _ => true
    },
  )
  let unknown = { ..record, format_version: 99, }
  assert_true(
    try {
      ignore(replay(unknown))
      false
    } catch {
      @records.RecordError::UnsupportedVersion(99) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(@records.select_case([record], "missing"))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(@records.select_case([record], record.case_id), record)
  assert_true(
    try {
      ignore(@records.select_case([record, record], record.case_id))
      false
    } catch {
      _ => true
    },
  )
}
