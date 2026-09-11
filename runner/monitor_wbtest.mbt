///|
test "callback lifecycle is ordered and monitor cannot edit recorded steps" {
  let events : Array[String] = []
  let monitor = Monitor::new(
    before=_ => events.push("before"),
    after=result => {
      events.push("after")
      result.steps.clear()
    },
    fault=_ => events.push("fault"),
    recover=_ => {
      events.push("recover")
      true
    },
  )
  let runner = Runner::with_dialer(
    runner_paths(),
    () => {
      { sent: [], responses: [], fail_at: 0, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor~,
  )
  let result = runner.next().unwrap()
  assert_eq(result.outcome, SendFailed(123))
  assert_eq(result.steps.length(), 1)
  assert_eq(events, ["before", "after", "fault", "recover"])
}

///|
test "recovery failure stops run and before callback failure never connects" {
  let connected = Ref(0)
  let monitor = Monitor::new(before=_ => fail("before failed"), recover=_ => {
    false
  })
  let runner = Runner::with_dialer(
    runner_paths(),
    () => {
      connected.val += 1
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor~,
  )
  assert_true(runner.next().unwrap().outcome is RecoveryFailed(_))
  assert_eq(connected.val, 0)
  assert_true(runner.next() is None)
  assert_eq(runner.state(), Stopped)
}

///|
test "timeout peer closure response mismatch and callback errors stay distinct" {
  let timeout = Runner::with_dialer(
    runner_paths(),
    () => {
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    policies={ "hello": Fixed(1) },
  )
  assert_eq(timeout.next().unwrap().outcome, ReceiveTimedOut)
  let closed = Runner::with_dialer(
    runner_paths(),
    () => {
      {
        sent: [],
        responses: [@transport.Closed],
        fail_at: -1,
        last_sent: 0,
        closed: false,
      }
      as &Channel
    },
    policies={ "hello": Fixed(1) },
  )
  assert_eq(closed.next().unwrap().outcome, PeerClosed)
  let mismatch = Runner::with_dialer(
    runner_paths(),
    () => {
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor=Monitor::new(check=(_, _) => false),
  )
  assert_eq(mismatch.next().unwrap().outcome, ResponseMismatch)
  let callback = Runner::with_dialer(
    runner_paths(),
    () => {
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor=Monitor::new(after=_ => fail("after failed")),
  )
  assert_true(callback.next().unwrap().outcome is CallbackFailed(_))
  let refused = Runner::with_dialer(runner_paths(), () => {
    raise @transport.TransportError::ConnectFailure(61)
  })
  assert_eq(refused.next().unwrap().outcome, ConnectFailed(61))
}
