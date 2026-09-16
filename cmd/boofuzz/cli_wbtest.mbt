///|
type FixtureSocket

///|
type FixtureFile

///|
extern "c" fn fixture_new() -> FixtureSocket = "bf_new"

///|
#borrow(socket)
extern "c" fn fixture_close(socket : FixtureSocket) -> Unit = "bf_close"

///|
#borrow(socket)
extern "c" fn fixture_listen(socket : FixtureSocket) -> Int = "bf_listen"

///|
#borrow(socket)
extern "c" fn fixture_udp(socket : FixtureSocket) -> Int = "bf_bind_udp"

///|
#borrow(socket)
extern "c" fn fixture_wait(
  socket : FixtureSocket,
  write : Int,
  timeout : Int,
) -> Int = "bf_wait"

///|
#borrow(listener, client)
extern "c" fn fixture_accept(
  listener : FixtureSocket,
  client : FixtureSocket,
) -> Int = "bf_accept"

///|
#borrow(socket, bytes)
extern "c" fn fixture_receive(
  socket : FixtureSocket,
  bytes : FixedArray[Byte],
  limit : Int,
) -> Int = "bf_recv"

///|
extern "c" fn fixture_path() -> Bytes = "bf_file_temp"

///|
#borrow(path)
extern "c" fn fixture_remove(path : Bytes) -> Unit = "bf_file_remove"

///|
#borrow(path)
extern "c" fn fixture_open(path : Bytes, write : Int) -> FixtureFile = "bf_file_open"

///|
#borrow(file, bytes)
extern "c" fn fixture_write(
  file : FixtureFile,
  bytes : Bytes,
  length : Int,
) -> Int = "bf_file_write"

///|
#borrow(file)
extern "c" fn fixture_file_close(file : FixtureFile) -> Unit = "bf_file_close"

///|
fn save_definition(path : Bytes, value : Json) -> Unit raise {
  let file = fixture_open(path, 1)
  defer fixture_file_close(file)
  let bytes = @utf8.encode(value.stringify() + "\n")
  assert_eq(fixture_write(file, bytes, bytes.length()), 0)
}

///|
test "CLI run completes TCP and UDP flows with portable records" {
  for udp in [false, true] {
    let server = fixture_new()
    defer fixture_close(server)
    let port = if udp { fixture_udp(server) } else { fixture_listen(server) }
    assert_true(port > 0)
    let definition_path = fixture_path()
    defer fixture_remove(definition_path)
    let output_path = fixture_path()
    defer fixture_remove(output_path)
    let definition : Json = {
      "schema_version": 1,
      "requests": [
        {
          "name": "r",
          "children": [
            { "type": "simple", "name": "data", "values_hex": ["00ff", "41"] },
          ],
        },
      ],
      "execution": {
        "transport": if udp {
          "udp"
        } else {
          "tcp"
        },
        "endpoint": { "host": "127.0.0.1", "port": port },
        "case_limit": 2,
      },
    }
    save_definition(definition_path, definition)
    assert_eq(
      dispatch([
        "run",
        @utf8.decode(definition_path),
        "--output",
        @utf8.decode(output_path),
      ]),
      0,
    )
    let records = @recordio.read_records(@utf8.decode(output_path))
    assert_true(records.error is None)
    assert_eq(records.records.length(), 2)
    for i, expected in [b"\x00\xff", b"A"] {
      assert_eq(records.records[i].steps[0].sent, expected)
      assert_eq(records.records[i].outcome, "passed")
      assert_eq(fixture_wait(server, 0, 1000), 1)
      let peer = if udp {
        server
      } else {
        let peer = fixture_new()
        assert_eq(fixture_accept(server, peer), 0)
        peer
      }
      let buffer = FixedArray::make(128, b'\x00')
      assert_eq(fixture_wait(peer, 0, 1000), 1)
      let n = fixture_receive(peer, buffer, 128)
      assert_true(n >= 0)
      assert_eq(Bytes::makei(n, j => buffer[j]), expected)
      if !udp {
        fixture_close(peer)
      }
    }
  }
}

///|
test "CLI rejects malformed definitions before any connection" {
  let server = fixture_new()
  defer fixture_close(server)
  let port = fixture_listen(server)
  let path = fixture_path()
  defer fixture_remove(path)
  save_definition(path, {
    "schema_version": 1,
    "requests": [],
    "unsupported": true,
    "execution": {
      "transport": "tcp",
      "endpoint": { "host": "127.0.0.1", "port": port },
    },
  })
  assert_true(
    try {
      ignore(dispatch(["run", @utf8.decode(path), "--output", "unused.jsonl"]))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(fixture_wait(server, 0, 10), 0)
  assert_true(
    try {
      ignore(dispatch(["generate", @utf8.decode(path), "--unknown", "x"]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "run with csv-out writes a report row per case" {
  let definition : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "packet",
        "children": [
          {
            "type": "simple",
            "name": "value",
            "value_hex": "6869",
            "values_hex": ["6f6b", "6c6f6e67"],
          },
        ],
      },
    ],
    "execution": {
      "transport": "udp",
      "endpoint": { "host": "127.0.0.1", "port": 1 },
      "policies": {},
      "case_limit": 2,
    },
  }
  let definition_path = fixture_path()
  save_definition(definition_path, definition)
  defer fixture_remove(definition_path)
  let records_path = fixture_path()
  defer fixture_remove(records_path)
  let csv_path = fixture_path()
  defer fixture_remove(csv_path)
  // No live target: both cases fail to connect but records are still written.
  let exit = dispatch([
    "run",
    @utf8.decode(definition_path),
    "--output",
    @utf8.decode(records_path),
    "--csv-out",
    @utf8.decode(csv_path),
  ])
  assert_eq(exit, 0)
  let csv = @utf8.decode(@recordio.read_bytes(@utf8.decode(csv_path)))
  let rows : Array[String] = []
  for part in csv.split("\n") {
    rows.push(part.to_owned())
  }
  assert_eq(
    rows[0],
    "case_id,ordinal,request_name,field_path,mutation_index,outcome,failed_step,sent_hex,received_hex",
  )
  assert_true(rows[1].contains("packet"))
  // UDP sends succeed without a listener and the none policy completes the
  // step, so the case outcome is passed.
  assert_true(rows[1].contains("passed"))
  assert_eq(
    @records.parse_jsonl_bytes(@recordio.read_bytes(@utf8.decode(records_path))).records.length(),
    2,
  )
}

///|
test "run with --db writes upstream-compatible SQLite results" {
  let definition : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "packet",
        "children": [
          {
            "type": "simple",
            "name": "value",
            "value_hex": "6869",
            "values_hex": ["6f6b", "6c6f6e67"],
          },
        ],
      },
    ],
    "execution": {
      "transport": "udp",
      "endpoint": { "host": "127.0.0.1", "port": 1 },
      "policies": {},
      "case_limit": 2,
    },
  }
  let definition_path = fixture_path()
  defer fixture_remove(definition_path)
  save_definition(definition_path, definition)
  let records_path = fixture_path()
  defer fixture_remove(records_path)
  let db_file = fixture_path()
  defer fixture_remove(db_file)
  assert_eq(
    dispatch([
      "run",
      @utf8.decode(definition_path),
      "--output",
      @utf8.decode(records_path),
      "--db",
      @utf8.decode(db_file),
    ]),
    0,
  )
  let reader = @db.DbReader::open(@utf8.decode(db_file))
  defer reader.close()
  assert_eq(
    reader.query("SELECT count(*) FROM cases")[0].values[0],
    @db.VInt(2L),
  )
  let case0 = reader.get_test_case_data(0)
  assert_eq(case0.name, "packet")
  // step, send, receive, pass — the upstream log sequence per case.
  assert_eq(case0.steps.length(), 4)
  assert_eq(case0.steps[1].step_type, "send")
  assert_eq(case0.steps[1].data, b"\x6f\x6b")
  assert_eq(case0.steps[2].step_type, "receive")
  assert_eq(case0.steps[3].step_type, "pass")
  assert_eq(reader.failure_map().length(), 0)
  // The JSONL side still carries the same two records.
  assert_eq(
    @recordio.read_records(@utf8.decode(records_path)).records.length(),
    2,
  )
}

///|
test "run with --record-passes keeps only the first and last window" {
  let definition : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "packet",
        "children": [
          {
            "type": "simple",
            "name": "value",
            "value_hex": "01",
            "values_hex": ["01", "02", "03", "04"],
          },
        ],
      },
    ],
    "execution": {
      "transport": "udp",
      "endpoint": { "host": "127.0.0.1", "port": 1 },
      "policies": {},
      "case_limit": 4,
    },
  }
  let definition_path = fixture_path()
  defer fixture_remove(definition_path)
  save_definition(definition_path, definition)
  let records_path = fixture_path()
  defer fixture_remove(records_path)
  let db_file = fixture_path()
  defer fixture_remove(db_file)
  assert_eq(
    dispatch([
      "run",
      @utf8.decode(definition_path),
      "--output",
      @utf8.decode(records_path),
      "--db",
      @utf8.decode(db_file),
      "--record-passes",
      "2",
    ]),
    0,
  )
  let expected : Array[Int] = [0, 2, 3]
  let ordinals = @recordio.read_records(@utf8.decode(records_path)).records.map(record => {
      record.ordinal
    },
  )
  assert_eq(ordinals, expected)
  let reader = @db.DbReader::open(@utf8.decode(db_file))
  defer reader.close()
  assert_eq(
    reader
    .query("SELECT number FROM cases ORDER BY number")
    .map(row => row.values[0]),
    [@db.VInt(0L), @db.VInt(2L), @db.VInt(3L)],
  )
}

///|
test "run with --web-port binds the UI and completes the run" {
  let definition : Json = {
    "schema_version": 1,
    "requests": [
      {
        "name": "packet",
        "children": [
          { "type": "simple", "name": "value", "values_hex": ["01", "02"] },
        ],
      },
    ],
    "execution": {
      "transport": "udp",
      "endpoint": { "host": "127.0.0.1", "port": 1 },
      "policies": {},
      "case_limit": 2,
    },
  }
  let definition_path = fixture_path()
  defer fixture_remove(definition_path)
  save_definition(definition_path, definition)
  let records_path = fixture_path()
  defer fixture_remove(records_path)
  assert_eq(
    dispatch([
      "run",
      @utf8.decode(definition_path),
      "--output",
      @utf8.decode(records_path),
      "--web-port",
      "0",
    ]),
    0,
  )
  assert_eq(
    @recordio.read_records(@utf8.decode(records_path)).records.length(),
    2,
  )
}
