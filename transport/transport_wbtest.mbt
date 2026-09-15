///|
#borrow(socket)
extern "c" fn listen_local(socket : Socket) -> Int = "bf_listen"

///|
#borrow(listener, client)
extern "c" fn accept_local(listener : Socket, client : Socket) -> Int = "bf_accept"

///|
test "TCP loopback bounded partial reads full send timeout EOF and repeated close" {
  let listener = socket_new()
  defer socket_close(listener)
  let port = listen_local(listener)
  assert_true(port > 0)
  let endpoint = Endpoint::new("localhost", port, receive_timeout_ms=30)
  let client = Connection::tcp(endpoint)
  defer client.close()
  assert_eq(socket_wait(listener, 0, 1000), 1)
  let peer_socket = socket_new()
  let peer : Connection = {
    socket: peer_socket,
    endpoint,
    closed: false,
    last_sent: 0,
    udp: false,
  }
  defer peer.close()
  assert_eq(accept_local(listener, peer_socket), 0)
  client.send(b"ABC\x00\xff")
  assert_eq(peer.receive(max_bytes=2), Data(b"AB"))
  assert_eq(peer.receive(), Data(b"C\x00\xff"))
  peer.send(b"reply")
  assert_eq(client.receive(), Data(b"reply"))
  let large = b"\x00\xff".repeat(20000)
  client.send(large)
  assert_eq(client.last_sent_len(), large.length())
  let collected : Array[Byte] = []
  while collected.length() < large.length() {
    guard peer.receive() is Data(bytes) else { fail("unexpected EOF") }
    for byte in bytes {
      collected.push(byte)
    }
  }
  assert_eq(Bytes::from_array(collected), large)
  client.send(b"")
  let before = now_ms()
  assert_true(
    try {
      ignore(client.receive())
      false
    } catch {
      Timeout(Receive) => true
      _ => false
    },
  )
  assert_true(now_ms() - before < 2000L)
  peer.close()
  peer.close()
  assert_eq(client.receive(), Closed)
  client.close()
  client.close()
  assert_true(
    try {
      client.send(b"X")
      false
    } catch {
      SendFailure(_) => true
      _ => false
    },
  )
}

///|
test "TCP unavailable listener fails within deadline and validates options" {
  let listener = socket_new()
  let port = listen_local(listener)
  assert_true(port > 0)
  socket_close(listener)
  let endpoint = Endpoint::new("127.0.0.1", port, connect_timeout_ms=100)
  for _ in 0..<3 {
    assert_true(
      try {
        let connection = Connection::tcp(endpoint)
        connection.close()
        false
      } catch {
        ConnectFailure(_) | Timeout(Connect) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      ignore(Endpoint::new("x", 0))
      false
    } catch {
      InvalidConfiguration(_) => true
      _ => false
    },
  )
  // IPv6 literals are valid endpoints now; "::1" must be accepted.
  ignore(Endpoint::new("::1", 80))
  assert_true(
    try {
      ignore(Endpoint::new("x", 80, send_timeout_ms=0))
      false
    } catch {
      InvalidConfiguration(_) => true
      _ => false
    },
  )
}

///|
#borrow(socket)
extern "c" fn listen6_local(socket : Socket) -> Int = "bf_listen6"

///|
test "TCP IPv6 loopback connects and exchanges bytes" {
  let listener = socket_new()
  defer socket_close(listener)
  let port = listen6_local(listener)
  assert_true(port > 0)
  let endpoint = Endpoint::new("::1", port, receive_timeout_ms=30)
  let client = Connection::tcp(endpoint)
  defer client.close()
  assert_eq(socket_wait(listener, 0, 1000), 1)
  let peer_socket = socket_new()
  let peer : Connection = {
    socket: peer_socket,
    endpoint,
    closed: false,
    last_sent: 0,
    udp: false,
  }
  defer peer.close()
  assert_eq(accept_local(listener, peer_socket), 0)
  client.send(b"V6\xff")
  assert_eq(peer.receive(), Data(b"V6\xff"))
  peer.send(b"ok")
  assert_eq(client.receive(), Data(b"ok"))
}
