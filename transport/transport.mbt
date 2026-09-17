///|
pub(all) enum Phase {
  Connect
  Send
  Receive
} derive(Debug, Eq)

///|
pub(all) suberror TransportError {
  InvalidConfiguration(String)
  ConnectFailure(Int)
  SendFailure(Int)
  ReceiveFailure(Int)
  Timeout(Phase)
  DatagramTooLarge
} derive(Debug)

///|
pub(all) enum Received {
  Data(Bytes)
  Closed
} derive(Debug, Eq)

///|
pub struct Endpoint {
  host : String
  port : Int
  connect_timeout_ms : Int
  send_timeout_ms : Int
  receive_timeout_ms : Int
  max_receive : Int
} derive(Debug, ToJson)

///|
pub fn Endpoint::new(
  host : String,
  port : Int,
  connect_timeout_ms? : Int = 5000,
  send_timeout_ms? : Int = 5000,
  receive_timeout_ms? : Int = 5000,
  max_receive? : Int = 65536,
  /// UDP server binds may use an empty host (wildcard) and port 0
  /// (ephemeral), like upstream's udp_socket_connection bind.
  udp_server? : Bool = false,
) -> Endpoint raise TransportError {
  guard !host.contains("\u0000") && (udp_server || !host.is_empty()) else {
    raise InvalidConfiguration("expected hostname/IPv4/IPv6 and port 1..65535")
  }
  guard port >= 0 && port <= 65535 && (udp_server || port > 0) else {
    raise InvalidConfiguration("expected hostname/IPv4/IPv6 and port 1..65535")
  }
  guard connect_timeout_ms > 0 &&
    send_timeout_ms > 0 &&
    receive_timeout_ms > 0 &&
    max_receive > 0 &&
    max_receive <= 1048576 else {
    raise InvalidConfiguration("invalid timeout or receive bound (1..1048576)")
  }
  {
    host,
    port,
    connect_timeout_ms,
    send_timeout_ms,
    receive_timeout_ms,
    max_receive,
  }
}

///|
pub struct Connection {
  socket : Socket
  endpoint : Endpoint
  mut closed : Bool
  mut last_sent : Int
  udp : Bool
  server : Bool
  broadcast : Bool
}

///|
pub fn Connection::tcp(endpoint : Endpoint) -> Connection raise TransportError {
  let socket = socket_new()
  errdefer socket_close(socket)
  match
    socket_connect(
      socket,
      @utf8.encode(endpoint.host),
      endpoint.port,
      endpoint.connect_timeout_ms,
      0,
    ) {
    0 =>
      {
        socket,
        endpoint,
        closed: false,
        last_sent: 0,
        udp: false,
        server: false,
        broadcast: false,
      }
    -2 => raise Timeout(Connect)
    _ => raise ConnectFailure(socket_error(socket))
  }
}

///|
pub fn Connection::close(self : Connection) -> Unit {
  if !self.closed {
    socket_close(self.socket)
    self.closed = true
  }
}

///|
fn Connection::wait_ready(
  self : Connection,
  phase : Phase,
  deadline : Int64,
) -> Unit raise TransportError {
  let remaining = deadline - now_ms()
  guard remaining > 0L else { raise Timeout(phase) }
  let result = socket_wait(
    self.socket,
    if phase == Send {
      1
    } else {
      0
    },
    remaining.to_int(),
  )
  if result == 0 {
    raise Timeout(phase)
  }
  if result < 0 {
    if phase == Send {
      raise SendFailure(socket_error(self.socket))
    } else {
      raise ReceiveFailure(socket_error(self.socket))
    }
  }
}

///|
/// Send the complete TCP buffer under one deadline; never retry a failed case.
pub fn Connection::send(
  self : Connection,
  bytes : Bytes,
) -> Unit raise TransportError {
  self.last_sent = 0
  guard !self.closed else { raise SendFailure(-1) }
  let deadline = now_ms() + self.endpoint.send_timeout_ms.to_int64()
  if self.udp && self.server {
    guard bytes.length() <= 65507 else { raise DatagramTooLarge }
    for ;; {
      self.wait_ready(Send, deadline)
      // -3 = no peer recorded yet: a distinct configuration error with
      // upstream's message, not a meaningless SendFailure(0)
      // (udp_socket_connection.py:114-116).
      let n = udp_send_to_peer(self.socket, bytes, bytes.length())
      if n == -3 {
        raise InvalidConfiguration(
          "recv() must be called before send with udp fuzzing servers",
        )
      }
      if n == -2 {
        continue
      }
      guard n >= 0 else { raise SendFailure(socket_error(self.socket)) }
      self.last_sent = n
      return
    }
  }
  if self.udp && self.broadcast {
    guard bytes.length() <= 65507 else { raise DatagramTooLarge }
    for ;; {
      self.wait_ready(Send, deadline)
      let n = udp_send_to_address(
        self.socket,
        @utf8.encode(self.endpoint.host),
        self.endpoint.host.length(),
        self.endpoint.port,
        bytes,
        bytes.length(),
      )
      if n == -2 {
        continue
      }
      guard n == bytes.length() else {
        if n == -4 {
          raise InvalidConfiguration("broadcast target must be an IPv4 literal")
        }
        raise SendFailure(socket_error(self.socket))
      }
      self.last_sent = n
      return
    }
  }
  if self.udp {
    guard bytes.length() <= 65507 else { raise DatagramTooLarge }
    for ;; {
      self.wait_ready(Send, deadline)
      let n = socket_send(self.socket, bytes, 0, bytes.length())
      if n == -2 {
        continue
      }
      guard n == bytes.length() else {
        raise SendFailure(socket_error(self.socket))
      }
      self.last_sent = n
      return
    }
  }
  for offset = 0; offset < bytes.length(); {
    self.wait_ready(Send, deadline)
    let sent = socket_send(
      self.socket,
      bytes,
      offset,
      (bytes.length() - offset).min(16384),
    )
    if sent == -2 {
      continue offset
    }
    guard sent > 0 else { raise SendFailure(socket_error(self.socket)) }
    self.last_sent += sent
    continue offset + sent
  }
}

///|
/// Number of bytes actually accepted by the last send, including partial failure.
pub fn Connection::last_sent_len(self : Connection) -> Int {
  self.last_sent
}

///|
/// Read at most max_bytes, distinguishing TCP EOF from a data buffer.
pub fn Connection::receive(
  self : Connection,
  max_bytes? : Int,
  timeout_ms? : Int,
) -> Received raise TransportError {
  guard !self.closed else { raise ReceiveFailure(-1) }
  let limit = max_bytes.unwrap_or(self.endpoint.max_receive)
  guard limit > 0 && limit <= self.endpoint.max_receive else {
    raise InvalidConfiguration("receive request exceeds configured bound")
  }
  let buffer = FixedArray::make(limit, b'\x00')
  let timeout = timeout_ms.unwrap_or(self.endpoint.receive_timeout_ms)
  guard timeout > 0 && timeout <= self.endpoint.receive_timeout_ms else {
    raise InvalidConfiguration("invalid receive timeout override")
  }
  let deadline = now_ms() + timeout.to_int64()
  if self.udp && (self.server || self.broadcast) {
    // Server and broadcast sockets recvfrom() unconnected: any source is
    // accepted and the last peer is recorded for server replies
    // (udp_socket_connection.py:73-79).
    for ;; {
      self.wait_ready(Receive, deadline)
      let n = udp_receive_from(self.socket, buffer, limit)
      if n == -2 {
        continue
      }
      if n == -3 {
        // Oversized datagram: consumed and rejected, matching the
        // connected path's behavior (docs/UDP.md).
        raise DatagramTooLarge
      }
      guard n >= 0 else { raise ReceiveFailure(socket_error(self.socket)) }
      return Data(Bytes::makei(n, i => buffer[i]))
    }
  }
  for ;; {
    self.wait_ready(Receive, deadline)
    let n = socket_receive(self.socket, buffer, limit)
    if n == -3 {
      raise DatagramTooLarge
    }
    if n == -2 {
      continue
    }
    guard n >= 0 else { raise ReceiveFailure(socket_error(self.socket)) }
    if n == 0 && !self.udp {
      return Closed
    }
    return Data(Bytes::makei(n, i => buffer[i]))
  }
}

///|
pub fn Endpoint::receive_limit(self : Endpoint) -> Int {
  self.max_receive
}

///|
pub fn Endpoint::receive_timeout(self : Endpoint) -> Int {
  self.receive_timeout_ms
}

///|
pub fn monotonic_ms() -> Int64 {
  now_ms()
}

///|
pub fn Endpoint::retarget(
  self : Endpoint,
  host : String,
  port : Int,
) -> Endpoint raise TransportError {
  Endpoint::new(
    host,
    port,
    connect_timeout_ms=self.connect_timeout_ms,
    send_timeout_ms=self.send_timeout_ms,
    receive_timeout_ms=self.receive_timeout_ms,
    max_receive=self.max_receive,
  )
}
