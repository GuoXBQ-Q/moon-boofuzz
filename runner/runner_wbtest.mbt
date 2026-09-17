///|
struct Mock {
  sent : Array[Bytes]
  responses : Array[@transport.Received]
  fail_at : Int
  mut last_sent : Int
  mut closed : Bool
}

///|
impl Channel for Mock with fn send(self, bytes) {
  self.last_sent = 0
  if self.sent.length() == self.fail_at {
    raise @transport.TransportError::SendFailure(123)
  }
  self.sent.push(bytes)
  self.last_sent = bytes.length()
}

///|
impl Channel for Mock with fn receive(self, _, _) {
  if self.responses.is_empty() {
    raise @transport.TransportError::Timeout(Receive)
  }
  self.responses.remove(0)
}

///|
impl Channel for Mock with fn last_sent_len(self) {
  self.last_sent
}

///|
impl Channel for Mock with fn close(self) {
  self.closed = true
}

///|
fn runner_paths() -> Array[@core.SessionPath] raise {
  let graph = @core.SessionGraph::new()
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("hello", [Leaf("x", @core.Field::simple(b"HELLO", []))]),
    ),
  )
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("query", [
        Leaf("x", @core.Field::simple(b"QUERY", [b"one", b"two"])),
      ]),
    ),
  )
  graph.connect("hello", "query")
  graph.paths(targets=["query"])
}

///|
test "each case reconnects and prerequisite failure prevents target send" {
  let sockets : Array[Mock] = []
  let runner = Runner::with_dialer(runner_paths(), fn() {
    let socket = {
      sent: [],
      responses: [],
      fail_at: if sockets.is_empty() {
        0
      } else {
        -1
      },
      last_sent: 0,
      closed: false,
    }
    sockets.push(socket)
    socket
  })
  let first = runner.next().unwrap()
  assert_eq(first.outcome, SendFailed(123))
  assert_eq(first.failed_step, Some(0))
  assert_eq(first.steps.length(), 1)
  let second = runner.next().unwrap()
  assert_eq(second.outcome, Passed)
  assert_eq(sockets.length(), 2)
  assert_eq(sockets[0].sent, [])
  assert_eq(sockets[1].sent, [b"HELLO", b"two"])
  assert_true(sockets[0].closed && sockets[1].closed)
  assert_true(runner.next() is None)
  assert_eq(runner.executed(), 2)
  assert_eq(runner.state(), Exhausted)
}

///|
test "fixed and delimiter responses retain buffered tail and respect case limit" {
  let runner = Runner::with_dialer(
    runner_paths(),
    () => {
      {
        sent: [],
        responses: [@transport.Data(b"OKresponse\r\n")],
        fail_at: -1,
        last_sent: 0,
        closed: false,
      }
      as &Channel
    },
    policies={ "hello": Fixed(2), "query": Until(b"\r\n") },
    limit=1,
  )
  let result = runner.next().unwrap()
  assert_eq(result.outcome, Passed)
  assert_eq(result.steps[0].received, b"OK")
  assert_eq(result.steps[1].received, b"response\r\n")
  assert_true(runner.next() is None)
  assert_eq(runner.state(), Limited)
  runner.stop()
  assert_eq(runner.state(), Stopped)
}

///|
test "dial failure retries within threshold then recovers" {
  let attempts : Array[Int] = []
  let mut fails = 2
  let runner = Runner::with_dialer(
    runner_paths(),
    fn() raise @transport.TransportError {
      attempts.push(attempts.length() + 1)
      if fails > 0 {
        fails -= 1
        raise @transport.TransportError::ConnectFailure(111)
      }
      let mock : Mock = {
        sent: [],
        responses: [],
        fail_at: -1,
        last_sent: 0,
        closed: false,
      }
      mock
    },
    restart_threshold=Some(3),
    restart_sleep_ms=0,
  )
  let result = runner.next().unwrap()
  assert_eq(result.outcome, Passed)
  // Two failed dials plus the successful one.
  assert_eq(attempts.length(), 3)
}

///|
test "dial failure counts failed dials and stops at the threshold" {
  // Upstream counts failed dials including the first and re-raises out of
  // the fuzz loop at the threshold, so threshold=2 allows exactly 2 dials.
  let attempts : Array[Int] = []
  let runner = Runner::with_dialer(
    runner_paths(),
    fn() raise @transport.TransportError {
      attempts.push(attempts.length() + 1)
      raise @transport.TransportError::ConnectFailure(111)
    },
    restart_threshold=Some(2),
    restart_sleep_ms=0,
  )
  let result = runner.next().unwrap()
  assert_eq(result.outcome, ConnectFailed(111))
  assert_eq(result.failed_step, Some(-1))
  assert_eq(attempts.length(), 2)
  // Giving up ends the run: the failed case is recorded, then no more.
  assert_true(runner.next() is None)
  assert_eq(runner.state(), Stopped)
  assert_eq(runner.executed(), 1)
}

///|
test "dial failure without threshold keeps retrying until timeout" {
  // restart_threshold defaults to None (infinite retries, like upstream);
  // restart_timeout_ms is the only bound in this configuration.
  let attempts : Array[Int] = []
  let runner = Runner::with_dialer(
    runner_paths(),
    fn() raise @transport.TransportError {
      attempts.push(attempts.length() + 1)
      raise @transport.TransportError::ConnectFailure(111)
    },
    restart_timeout_ms=120,
    restart_sleep_ms=10,
  )
  let result = runner.next().unwrap()
  assert_eq(result.outcome, ConnectFailed(111))
  assert_true(attempts.length() >= 2)
  assert_true(runner.next() is None)
  assert_eq(runner.state(), Stopped)
}

///|
test "recovered dial runs the case and recover is invoked per attempt" {
  let attempts : Array[Int] = []
  let recoveries : Array[Int] = []
  let mut fails = 1
  let monitor = Monitor::new(recover=fn(_result) {
    recoveries.push(recoveries.length() + 1)
    true
  })
  let runner = Runner::with_dialer(
    runner_paths(),
    fn() raise @transport.TransportError {
      attempts.push(attempts.length() + 1)
      if fails > 0 {
        fails -= 1
        raise @transport.TransportError::Timeout(Connect)
      }
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor~,
    restart_threshold=Some(2),
    restart_sleep_ms=0,
  )
  let result = runner.next().unwrap()
  assert_eq(result.outcome, Passed)
  // ConnectTimedOut takes the same retry path as ConnectFailed.
  assert_eq(attempts.length(), 2)
  assert_eq(recoveries.length(), 1)
}

///|
test "crash threshold counts per path and spares other paths" {
  // Upstream exhausts only the failing fuzz node. Path a drains at the
  // request threshold of 2; path b's later failures count toward b's own
  // counter, so b keeps all of its cases.
  let graph = @core.SessionGraph::new()
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("a", [Leaf("x", @core.Field::simple(b"A", [b"1", b"2"]))]),
    ),
  )
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("b", [
        Leaf("y", @core.Field::simple(b"B", [b"3", b"4", b"5"])),
      ]),
    ),
  )
  let dials : Array[Int] = []
  let runner = Runner::with_dialer(
    graph.paths(),
    fn() {
      dials.push(dials.length() + 1)
      // Path a's two cases always fail; b:0 passes, b:1 and b:2 fail.
      let fail_at = if dials.length() <= 2 || dials.length() >= 4 {
        0
      } else {
        -1
      }
      { sent: [], responses: [], fail_at, last_sent: 0, closed: false, }
      as &Channel
    },
    crash_threshold_request=2,
    sleep_between_ms=0,
  )
  let outcomes : Array[String] = []
  while runner.next() is Some(result) {
    outcomes.push(
      result.case.request_name +
      ":" +
      result.case.field_path +
      ":\{result.case.mutation_index}",
    )
  }
  assert_eq(runner.state(), Exhausted)
  // a drains at its own threshold; b's counter starts fresh, so b:2 runs.
  assert_eq(outcomes, ["a:a.x:0", "a:a.x:1", "b:b.y:0", "b:b.y:1", "b:b.y:2"])
}

///|
test "element crash threshold skips the element but keeps the next element" {
  // One request with two elements of three candidates each; element x
  // reaches the threshold of 3, so its remaining candidates drain while
  // element y's first case is preserved.
  let graph = @core.SessionGraph::new()
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("r", [
        Leaf("x", @core.Field::simple(b"X", [b"1", b"2", b"3"])),
        Leaf("y", @core.Field::simple(b"Y", [b"4", b"5", b"6"])),
      ]),
    ),
  )
  let runner = Runner::with_dialer(
    graph.paths(),
    fn() {
      { sent: [], responses: [], fail_at: 0, last_sent: 0, closed: false, }
      as &Channel
    },
    crash_threshold_element=3,
    sleep_between_ms=0,
  )
  let outcomes : Array[String] = []
  while runner.next() is Some(result) {
    outcomes.push(result.case.field_path + ":\{result.case.mutation_index}")
  }
  assert_eq(runner.state(), Exhausted)
  // x:0/1/2 execute and count; x's list has no remainder beyond the three
  // candidates, and y keeps all three cases including its first.
  assert_eq(outcomes, ["r.x:0", "r.x:1", "r.x:2", "r.y:0", "r.y:1", "r.y:2"])
}

///|
test "run stops at the end index and start is a global ordinal" {
  let graph = @core.SessionGraph::new()
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("a", [Leaf("x", @core.Field::simple(b"A", [b"1", b"2"]))]),
    ),
  )
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("b", [Leaf("y", @core.Field::simple(b"B", [b"3", b"4"]))]),
    ),
  )
  // start=1 skips a's first case; end=3 stops after b's first case, so
  // b's second case never runs. Ordinals are global across paths.
  let runner = Runner::with_dialer(
    graph.paths(),
    fn() {
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    start=1,
    end=Some(3),
    sleep_between_ms=0,
  )
  let first = runner.next().unwrap()
  assert_eq(first.case.request_name, "a")
  assert_eq(first.case.mutation_index, 1)
  let second = runner.next().unwrap()
  assert_eq(second.case.request_name, "b")
  assert_eq(second.case.mutation_index, 0)
  assert_true(runner.next() is None)
  assert_eq(runner.state(), Limited)
  assert_eq(runner.executed(), 2)
}

///|
/// Mock whose send fails with a connection-reset errno (ECONNRESET) at the
/// configured send index, for exercising the ignore flags. Field names
/// differ from Mock so `{ ... } as &Channel` literals stay unambiguous.
struct ResetMock {
  out : Array[Bytes]
  reset_at : Int
  replies : Array[@transport.Received]
  mut last_sent : Int
}

///|
impl Channel for ResetMock with fn send(self, bytes) {
  self.last_sent = 0
  if self.out.length() == self.reset_at {
    raise @transport.TransportError::SendFailure(104)
  }
  self.out.push(bytes)
  self.last_sent = bytes.length()
}

///|
impl Channel for ResetMock with fn receive(self, _, _) {
  if self.replies.is_empty() {
    raise @transport.TransportError::Timeout(Receive)
  }
  self.replies.remove(0)
}

///|
impl Channel for ResetMock with fn last_sent_len(self) {
  self.last_sent
}

///|
impl Channel for ResetMock with fn close(self) {
  self.last_sent = 0
}

///|
test "ignored prefix send reset is not a counted failure" {
  let runner = Runner::with_dialer(
    runner_paths(),
    fn() { { out: [], reset_at: 0, replies: [], last_sent: 0, } as &Channel },
    ignore_connection_reset=true,
  )
  let first = runner.next().unwrap()
  assert_true(first.outcome is ConnectionIgnored(_))
  assert_eq(first.failed_step, Some(0))
  // Not counted: the run keeps going through every case.
  assert_eq(runner.state(), Running)
  let second = runner.next().unwrap()
  assert_true(second.outcome is ConnectionIgnored(_))
  assert_true(runner.next() is None)
  assert_eq(runner.state(), Exhausted)
}

///|
test "fuzzed-node send reset is ignored by default" {
  let runner = Runner::with_dialer(runner_paths(), fn() {
    { out: [], reset_at: 1, replies: [], last_sent: 0, } as &Channel
  })
  let first = runner.next().unwrap()
  assert_true(first.outcome is ConnectionIgnored(_))
  assert_eq(first.failed_step, Some(1))
}

///|
test "receive timeout is a failure only with check_data_received" {
  let lenient = Runner::with_dialer(
    runner_paths(),
    fn() { { out: [], reset_at: -1, replies: [], last_sent: 0, } as &Channel },
    policies={ "hello": Fixed(1) },
  )
  // Recorded for the report, but not a counted failure and no recovery.
  assert_eq(lenient.next().unwrap().outcome, ReceiveTimedOut)
  assert_eq(lenient.state(), Running)
  assert_eq(lenient.next().unwrap().outcome, ReceiveTimedOut)
  assert_true(lenient.next() is None)
  assert_eq(lenient.state(), Exhausted)
  let checked = Runner::with_dialer(
    runner_paths(),
    fn() { { out: [], reset_at: -1, replies: [], last_sent: 0, } as &Channel },
    policies={ "hello": Fixed(1) },
    check_data_received=true,
  )
  assert_eq(checked.next().unwrap().outcome, NothingReceived)
}

///|
test "receive_data_after_fuzz reads under the none policy" {
  let runner = Runner::with_dialer(
    runner_paths(),
    fn() {
      {
        sent: [],
        fail_at: -1,
        responses: [@transport.Data(b"ACK"), @transport.Data(b"ACK")],
        last_sent: 0,
        closed: false,
      }
      as &Channel
    },
    receive_data_after_fuzz=true,
  )
  let first = runner.next().unwrap()
  assert_eq(first.outcome, Passed)
  // The prefix step reads nothing; the fuzzed step records the read.
  assert_eq(first.steps[0].received, b"")
  assert_eq(first.steps[1].received, b"ACK")
}
