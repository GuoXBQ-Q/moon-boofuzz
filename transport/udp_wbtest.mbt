///|
#borrow(socket)
extern "c" fn bind_udp(socket : Socket) -> Int = "bf_bind_udp"

///|
#borrow(socket)
extern "c" fn local_port(socket : Socket) -> Int = "bf_port"

///|
#borrow(socket, buffer)
extern "c" fn udp_receive_peer(
  socket : Socket,
  buffer : FixedArray[Byte],
  length : Int,
) -> Int = "bf_udp_receive_peer"

///|
#borrow(socket, buffer)
extern "c" fn udp_send_port(
  socket : Socket,
  port : Int,
  buffer : Bytes,
  length : Int,
) -> Int = "bf_udp_send_port"

///|
test "UDP preserves empty and binary datagrams filters source and rejects truncation" {
  let server_socket = socket_new()
  let port = bind_udp(server_socket)
  assert_true(port > 0)
  let endpoint = Endpoint::new("127.0.0.1", port, receive_timeout_ms=40)
  let server : Connection = {
    socket: server_socket,
    endpoint,
    closed: false,
    last_sent: 0,
    udp: true,
  }
  defer server.close()
  let client = Connection::udp(endpoint)
  defer client.close()
  client.send(b"\x00\xffhello")
  assert_eq(socket_wait(server_socket, 0, 1000), 1)
  let buffer = FixedArray::make(32, b'\x00')
  let n = udp_receive_peer(server_socket, buffer, 32)
  assert_eq(n, 7)
  server.send(Bytes::makei(n, i => buffer[i]))
  assert_eq(client.receive(), Data(b"\x00\xffhello"))
  client.send(b"")
  assert_eq(server.receive(), Data(b""))
  server.send(b"")
  assert_eq(client.receive(), Data(b""))
  let stranger = socket_new()
  defer socket_close(stranger)
  assert_true(bind_udp(stranger) > 0)
  assert_eq(udp_send_port(stranger, local_port(client.socket), b"bad", 3), 3)
  assert_true(
    try {
      ignore(client.receive())
      false
    } catch {
      Timeout(Receive) => true
      _ => false
    },
  )
  server.send(b"ABCD")
  assert_true(
    try {
      ignore(client.receive(max_bytes=2))
      false
    } catch {
      DatagramTooLarge => true
      _ => false
    },
  )
  server.send(b"OK")
  assert_eq(client.receive(), Data(b"OK"))
  assert_true(
    try {
      client.send(b"A".repeat(65508))
      false
    } catch {
      DatagramTooLarge => true
      _ => false
    },
  )
}

///|
test "UDP rejects multicast broadcast and unspecified destinations" {
  for host in ["224.0.0.1", "255.255.255.255", "0.0.0.0"] {
    assert_true(
      try {
        let connection = Connection::udp(Endpoint::new(host, 9000))
        connection.close()
        false
      } catch {
        InvalidConfiguration(_) => true
        _ => false
      },
    )
  }
}
