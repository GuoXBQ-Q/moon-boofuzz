// SPDX-License-Identifier: GPL-2.0-only
// UDP connection modes, porting connections/udp_socket_connection.py at
// 518c139: connected (client), server (bind + recvfrom peer + sendto
// peer) and broadcast (SO_BROADCAST + unconnected sendto).

///|
/// Connected UDP filters packets by the selected peer and preserves datagrams.
pub fn Connection::udp(endpoint : Endpoint) -> Connection raise TransportError {
  let socket = socket_new()
  errdefer socket_close(socket)
  match
    socket_connect(
      socket,
      @utf8.encode(endpoint.host),
      endpoint.port,
      endpoint.connect_timeout_ms,
      1,
    ) {
    0 =>
      {
        socket,
        endpoint,
        closed: false,
        last_sent: 0,
        udp: true,
        server: false,
        broadcast: false,
      }
    -2 => raise Timeout(Connect)
    -3 => raise InvalidConfiguration("UDP destination must be unicast IPv4")
    _ => raise ConnectFailure(socket_error(socket))
  }
}

///|
/// Server-mode UDP: bind host:port (SO_REUSEADDR), record the last peer
/// on every recvfrom and answer it via sendto. An empty host binds the
/// wildcard address and port 0 asks for an ephemeral port, readable via
/// `local_port()`. send before any receive fails like upstream's
/// BoofuzzError (udp_socket_connection.py:36-133).
pub fn Connection::udp_server(
  endpoint : Endpoint,
) -> Connection raise TransportError {
  let socket = socket_new()
  errdefer socket_close(socket)
  let host = @utf8.encode(endpoint.host)
  if udp_server_bind(socket, host, host.length(), endpoint.port) != 0 {
    raise ConnectFailure(socket_error(socket))
  }
  // Resolve an ephemeral bind so the endpoint names the real port.
  let endpoint = if endpoint.port == 0 {
    let port = udp_local_port(socket)
    guard port > 0 else { raise ConnectFailure(socket_error(socket)) }
    { ..endpoint, port, }
  } else {
    endpoint
  }
  {
    socket,
    endpoint,
    closed: false,
    last_sent: 0,
    udp: true,
    server: true,
    broadcast: false,
  }
}

///|
/// The bound local port: resolved actual port after an ephemeral server
/// bind, the endpoint port for other server sockets, and a best-effort
/// getsockname query otherwise.
pub fn Connection::local_port(self : Connection) -> Int {
  if self.server {
    self.endpoint.port
  } else {
    let port = udp_local_port(self.socket)
    if port > 0 {
      port
    } else {
      self.endpoint.port
    }
  }
}

///|
/// Broadcast UDP: SO_BROADCAST on an unconnected socket; every send goes
/// to endpoint.host:port via sendto and receives accept any source
/// (udp_socket_connection.py:65-67).
pub fn Connection::udp_broadcast(
  endpoint : Endpoint,
) -> Connection raise TransportError {
  let socket = socket_new()
  errdefer socket_close(socket)
  if udp_broadcast_enable(socket) != 0 {
    raise ConnectFailure(socket_error(socket))
  }
  {
    socket,
    endpoint,
    closed: false,
    last_sent: 0,
    udp: true,
    server: false,
    broadcast: true,
  }
}
