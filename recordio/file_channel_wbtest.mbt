// File transport: one numbered file per message, runner integration with
// the NoResponse policy, and directory creation.

///|

///|
test "file channel writes one numbered file per message" {
  let base = temp_path()
  let directory = @utf8.decode(base) + ".dir"
  let channel = FileChannel::open(directory~)
  @runner.Channel::send(channel, b"one")
  @runner.Channel::send(channel, b"two\x00")
  assert_eq(@runner.Channel::last_sent_len(channel), 4)
  @runner.Channel::close(channel)
  assert_eq(read_bytes(directory + "/case-1"), b"one")
  assert_eq(read_bytes(directory + "/case-2"), b"two\x00")
  remove_temp(@utf8.encode(directory + "/case-1"))
  remove_temp(@utf8.encode(directory + "/case-2"))
  remove_temp(@utf8.encode(directory))
}

///|
test "file channel runs through the runner with none policies" {
  let base = temp_path()
  let directory = @utf8.decode(base) + ".dir2"
  let graph = @core.SessionGraph::new()
  graph.add(
    @core.CompiledRequest::compile(
      @core.Block::new("hello", [
        Leaf("x", @core.Field::simple(b"HELLO", [b"TWO", b"THREE"])),
      ]),
    ),
  )
  let paths = graph.paths()
  let config : @runner.ExecutionConfig = {
    endpoint: @transport.Endpoint::new("file", 1),
    udp: false,
    udp_server: false,
    udp_broadcast: false,
    policies: Map([]),
    limit: 10,
    combinatorial: false,
    max_depth: None,
    variables: Map([]),
    check_data_received: false,
    receive_data_after_fuzz: false,
    ignore_connection_reset: false,
    ignore_connection_aborted: false,
    ignore_connection_issues_when_sending_fuzz_data: true,
    restart_threshold: None,
    restart_timeout_ms: None,
    restart_sleep_ms: 5000,
    sleep_between_ms: 0,
    crash_threshold_request: 12,
    crash_threshold_element: 3,
    target_command: None,
    target_start_delay_ms: 1000,
    target_stop_delay_ms: 500,
    file_path: Some(directory),
  }
  // Control: direct channel send works in this same directory.
  let probe = FileChannel::open(directory~)
  @runner.Channel::send(probe, b"probe")
  @runner.Channel::close(probe)
  assert_eq(read_bytes(directory + "/case-1"), b"probe")
  remove_temp(@utf8.encode(directory + "/case-1"))
  let runner = file_runner(config, paths, limit=10)
  let first = runner.next().unwrap()
  assert_eq(first.outcome, Passed)
  assert_eq(first.steps[0].sent, b"TWO")
  let second = runner.next().unwrap()
  assert_eq(second.outcome, Passed)
  assert_eq(second.steps[0].sent, b"THREE")
  assert_eq(read_bytes(directory + "/case-1"), b"TWO")
  assert_eq(read_bytes(directory + "/case-2"), b"THREE")
  remove_temp(@utf8.encode(directory + "/case-1"))
  remove_temp(@utf8.encode(directory + "/case-2"))
  remove_temp(@utf8.encode(directory))
}
