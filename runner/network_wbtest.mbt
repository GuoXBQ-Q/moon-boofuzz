///|
type TestSocket

///|
extern "c" fn fixture_new() -> TestSocket = "bf_new"

///|
#borrow(socket)
extern "c" fn fixture_close(socket : TestSocket) -> Unit = "bf_close"

///|
#borrow(socket)
extern "c" fn fixture_listen(socket : TestSocket) -> Int = "bf_listen"

///|
#borrow(socket)
extern "c" fn fixture_udp(socket : TestSocket) -> Int = "bf_bind_udp"

///|
#borrow(socket)
extern "c" fn fixture_wait(
  socket : TestSocket,
  write : Int,
  timeout : Int,
) -> Int = "bf_wait"

///|
#borrow(listener, client)
extern "c" fn fixture_accept(listener : TestSocket, client : TestSocket) -> Int = "bf_accept"

///|
#borrow(socket, bytes)
extern "c" fn fixture_receive(
  socket : TestSocket,
  bytes : FixedArray[Byte],
  limit : Int,
) -> Int = "bf_recv"

///|
test "real TCP runner creates a distinct connection per prerequisite sequence" {
  let listener = fixture_new()
  defer fixture_close(listener)
  let port = fixture_listen(listener)
  assert_true(port > 0)
  let runner = Runner::new(
    runner_paths(),
    @transport.Endpoint::new("127.0.0.1", port),
  )
  for expected in [b"HELLOone", b"HELLOtwo"] {
    assert_eq(runner.next().unwrap().outcome, Passed)
    assert_eq(fixture_wait(listener, 0, 1000), 1)
    let accepted = fixture_new()
    defer fixture_close(accepted)
    assert_eq(fixture_accept(listener, accepted), 0)
    let collected : Array[Byte] = []
    let buffer = FixedArray::make(128, b'\x00')
    for ;; {
      assert_eq(fixture_wait(accepted, 0, 1000), 1)
      let n = fixture_receive(accepted, buffer, 128)
      assert_true(n >= 0)
      if n == 0 {
        break
      }
      for i in 0..<n {
        collected.push(buffer[i])
      }
    }
    assert_eq(Bytes::from_array(collected), expected)
  }
}

///|
test "real UDP runner sends separate prerequisite and target datagrams" {
  let server = fixture_new()
  defer fixture_close(server)
  let port = fixture_udp(server)
  assert_true(port > 0)
  let runner = Runner::new(
    runner_paths(),
    @transport.Endpoint::new("127.0.0.1", port),
    udp=true,
  )
  assert_eq(runner.next().unwrap().outcome, Passed)
  assert_eq(runner.next().unwrap().outcome, Passed)
  for expected in [b"HELLO", b"one", b"HELLO", b"two"] {
    assert_eq(fixture_wait(server, 0, 1000), 1)
    let buffer = FixedArray::make(128, b'\x00')
    let n = fixture_receive(server, buffer, 128)
    assert_true(n >= 0)
    assert_eq(Bytes::makei(n, i => buffer[i]), expected)
  }
}
