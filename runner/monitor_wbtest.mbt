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
test "monitor signal fails the case and drives fault and recover" {
  // Upstream: post_send returning False -> log_fail -> counted failure plus
  // target restart (session.py:507-548, 569-632). The port maps
  // MonitorSignal to the counted MonitorFailed outcome, so unlike a plain
  // after-callback exception the fault/recover pair runs for it.
  let events : Array[String] = []
  let monitor = Monitor::new(
    after=_ => {
      events.push("after")
      raise MonitorSignal::TargetFailed(reason="target crashed")
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
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor~,
  )
  let first = runner.next().unwrap()
  assert_true(first.outcome is MonitorFailed(_))
  assert_eq(events, ["after", "fault", "recover"])
  // The run continues: recovery succeeded, so the next case still runs and
  // is reported the same way.
  let second = runner.next().unwrap()
  assert_true(second.outcome is MonitorFailed(_))
  assert_true(runner.next() is None)
  assert_eq(runner.state(), Exhausted)
}

///|
test "fault callback exception keeps the counted failure classification" {
  // A raising fault callback must not rewrite the outcome to a non-counted
  // CallbackFailed; recovery still decides whether the run continues.
  let monitor = Monitor::new(
    after=_ => raise MonitorSignal::TargetFailed(reason="target crashed"),
    fault=_ => fail("fault failed"),
    recover=_ => true,
  )
  let runner = Runner::with_dialer(
    runner_paths(),
    () => {
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor~,
  )
  let result = runner.next().unwrap()
  assert_true(result.outcome is MonitorFailed(_))
  assert_eq(runner.state(), Running)
}

///|
test "before callback failure never connects and is not a counted failure" {
  // Upstream logs callback exceptions without failing the case
  // (monitors/callback_monitor.py); the port records CallbackFailed but
  // does not run fault/recover for it.
  let connected = Ref(0)
  let monitor = Monitor::new(before=_ => fail("before failed"))
  let runner = Runner::with_dialer(
    runner_paths(),
    () => {
      connected.val += 1
      { sent: [], responses: [], fail_at: -1, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor~,
  )
  let first = runner.next().unwrap()
  assert_true(first.outcome is CallbackFailed(_))
  assert_eq(connected.val, 0)
  // The run continues: no recovery is attempted for callback errors.
  assert_eq(runner.state(), Running)
  let second = runner.next().unwrap()
  assert_true(second.outcome is CallbackFailed(_))
  assert_true(runner.next() is None)
  assert_eq(runner.state(), Exhausted)
  assert_eq(runner.executed(), 2)
}

///|
test "recovery failure stops the run on a counted failure" {
  let monitor = Monitor::new(recover=_ => false)
  let runner = Runner::with_dialer(
    runner_paths(),
    () => {
      { sent: [], responses: [], fail_at: 0, last_sent: 0, closed: false, }
      as &Channel
    },
    monitor~,
  )
  let result = runner.next().unwrap()
  assert_true(result.outcome is RecoveryFailed(_))
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
  // The default restart_threshold retries indefinitely, so this always-
  // refusing dialer needs an explicit threshold of 1 (give up after one
  // restart and its failed re-dial, like upstream's threshold semantics).
  let refused = Runner::with_dialer(
    runner_paths(),
    () => raise @transport.TransportError::ConnectFailure(61),
    restart_threshold=Some(1),
    restart_sleep_ms=0,
  )
  assert_eq(refused.next().unwrap().outcome, ConnectFailed(61))
}
