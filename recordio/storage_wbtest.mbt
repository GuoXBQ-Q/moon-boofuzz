///|
extern "c" fn temp_path() -> Bytes = "bf_file_temp"

///|
#borrow(path)
extern "c" fn remove_temp(path : Bytes) -> Unit = "bf_file_remove"

///|
test "file records flush per line round trip and reject partial tail append" {
  let path_bytes = temp_path()
  assert_true(!path_bytes.is_empty())
  defer remove_temp(path_bytes)
  let path = @utf8.decode(path_bytes)
  let writer = Writer::open(path)
  defer writer.close()
  let record : @records.CaseRecord = {
    format_version: 1,
    case_id: "id",
    generator_version: "v1",
    request_name: "r",
    field_path: "r.x",
    mutation_index: 0,
    ordinal: 0,
    path: ["r"],
    config: {},
    steps: [
      { request_name: "r", sent: b"\x00\xff", received: b"", completed: true, },
    ],
    outcome: "passed",
    detail: "",
    failed_step: None,
  }
  writer.append(record)
  assert_eq(read_records(path).records, [record])
  assert_eq(write_file(writer.file, b"{", 1), 0)
  writer.close()
  let read = read_records(path)
  assert_eq(read.records, [record])
  assert_true(read.error is Some(_))
  assert_true(
    try {
      let bad = Writer::open(path)
      bad.close()
      false
    } catch {
      OpenFailure(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      writer.append(record)
      false
    } catch {
      WriteFailure(_) => true
      _ => false
    },
  )
}

///|
struct StoreMock {
  mut sent : Int
}

///|
impl @runner.Channel for StoreMock with fn send(self, bytes) {
  self.sent = bytes.length()
}

///|
impl @runner.Channel for StoreMock with fn receive(_, _, _) {
  @transport.Closed
}

///|
impl @runner.Channel for StoreMock with fn last_sent_len(self) {
  self.sent
}

///|
impl @runner.Channel for StoreMock with fn close(_) {
  ()
}

///|
test "persistence error stops before executing the next case" {
  let path_bytes = temp_path()
  defer remove_temp(path_bytes)
  let writer = Writer::open(@utf8.decode(path_bytes))
  writer.close()
  let graph = @core.SessionGraph::new()
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("r", [Leaf("x", @core.Field::simple(b"A", [b"B", b"C"]))]),
    ),
  )
  let dialed = Ref(0)
  let runner = @runner.Runner::with_dialer(graph.paths(), () => {
    dialed.val += 1
    StoreMock::{ sent: 0, } as &@runner.Channel
  })
  assert_true(
    try {
      ignore(capture(runner, writer))
      false
    } catch {
      WriteFailure(_) => true
      _ => false
    },
  )
  assert_eq(dialed.val, 1)
  assert_eq(runner.executed(), 1)
  assert_eq(runner.state(), Stopped)
}
