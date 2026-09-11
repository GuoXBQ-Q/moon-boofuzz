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
  assert_true(first.outcome is Failed(_))
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
