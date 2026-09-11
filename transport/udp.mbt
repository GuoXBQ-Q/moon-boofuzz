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
    0 => { socket, endpoint, closed: false, last_sent: 0, udp: true, }
    -2 => raise Timeout(Connect)
    -3 => raise InvalidConfiguration("UDP destination must be unicast IPv4")
    _ => raise ConnectFailure(socket_error(socket))
  }
}
