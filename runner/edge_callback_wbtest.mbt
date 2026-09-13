// Edge callbacks (challenge-response): the callback sees earlier responses
// and the case's session variables, may write variables that dynamic fields
// of the same case resolve, and may replace the step's sent data — following
// upstream sessions/session.py:754-794 at 518c139.

///|
struct CallbackMock {
  sent : Array[Bytes]
  responses : Array[@transport.Received]
  mut last_sent : Int
}

///|
impl Channel for CallbackMock with fn send(self, bytes) {
  self.last_sent = 0
  self.sent.push(bytes)
  self.last_sent = bytes.length()
}

///|
impl Channel for CallbackMock with fn receive(self, _, _) {
  if self.responses.is_empty() {
    raise @transport.TransportError::Timeout(Receive)
  }
  self.responses.remove(0)
}

///|
impl Channel for CallbackMock with fn last_sent_len(self) {
  self.last_sent
}

///|
impl Channel for CallbackMock with fn close(self) {
  ignore(self)
}

///|
fn callback_graph(write_only : Bool) -> Array[@core.SessionPath] raise {
  let graph = @core.SessionGraph::new()
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("hello", [Leaf("x", @core.Field::simple(b"HELLO", []))]),
    ),
  )
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("query", [
        @core.Node::dynamic(
          "token",
          "auth",
          @core.Field::simple(b"TOKEN", [b"mutant"]),
        ),
        Leaf("z", @core.Field::simple(b"Z", [b"Q"])),
      ]),
    ),
  )
  graph.connect("hello", "query", callback=fn(ctx) {
    let challenge = if ctx.received.is_empty() { b"" } else { ctx.received[0] }
    ctx.variables["auth"] = challenge
    if write_only {
      None
    } else {
      Some(b"AUTH-" + challenge)
    }
  })
  graph.paths(targets=["query"])
}

///|
fn callback_runner(
  write_only : Bool,
  responses : Array[@transport.Received],
) -> Runner raise {
  let mocks : Array[CallbackMock] = []
  let policies : Map[String, ReadPolicy] = Map([("hello", Fixed(5))])
  Runner::with_dialer(
    callback_graph(write_only),
    fn() {
      let mock : CallbackMock = { sent: [], responses, last_sent: 0, }
      mocks.push(mock)
      mock
    },
    policies~,
  )
}

///|
test "edge callback writes session variables consumed by dynamic fields" {
  let runner = callback_runner(true, [Data(b"CHALL"), Data(b"CHALL")])
  // Case 1 mutates token: the candidate renders regardless of variables.
  let first = runner.next().unwrap()
  assert_eq(first.outcome, Passed)
  assert_eq(first.steps[0].sent, b"HELLO")
  assert_eq(first.steps[0].received, b"CHALL")
  assert_eq(first.steps[1].sent, b"mutantZ")
  // Case 2 mutates z: the token default resolves from the variable the
  // callback wrote from the challenge response.
  let second = runner.next().unwrap()
  assert_eq(second.outcome, Passed)
  assert_eq(second.steps[1].sent, b"CHALLQ")
}

///|
test "edge callback replaces the step data when it returns bytes" {
  let runner = callback_runner(false, [Data(b"CHALL"), Data(b"CHALL")])
  // Both cases send the callback's replacement; upstream replaces the whole
  // node render including the mutated payload (session.py:791-794).
  let first = runner.next().unwrap()
  assert_eq(first.outcome, Passed)
  assert_eq(first.steps[1].sent, b"AUTH-CHALL")
  let second = runner.next().unwrap()
  assert_eq(second.outcome, Passed)
  assert_eq(second.steps[1].sent, b"AUTH-CHALL")
}
