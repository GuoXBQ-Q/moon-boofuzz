// SPDX-License-Identifier: GPL-2.0-only
// Public raw loopback TCP server over the same C bridge as `HttpServer`,
// for callers that implement their own protocol parsing — the httpd fuzz
// target in cmd/httpd. No HTTP logic lives here: bind, accept, wait,
// read, write, close.

///|
pub struct RawServer {
  socket : WebSocket
  bound_port : Int
}

///|
pub struct RawConn {
  socket : WebSocket
}

///|
/// Bind a loopback port strictly. Unlike `HttpServer::bind` this never
/// advances to the next port: a fuzz target asked for port N must fail
/// loudly when N is occupied instead of drifting to N+1.
pub fn RawServer::bind(port~ : Int) -> RawServer raise WebError {
  let socket = web_socket_new()
  if web_socket_error(socket) != 0 {
    raise BindFailure(web_socket_error(socket))
  }
  let bound = web_listen(socket, port)
  guard bound > 0 else {
    let code = web_socket_error(socket)
    web_socket_close(socket)
    raise BindFailure(code)
  }
  { socket, bound_port: bound, }
}

///|
pub fn RawServer::port(self : RawServer) -> Int {
  self.bound_port
}

///|
/// Accept one pending connection, waiting up to `timeout_ms`. Returns
/// None when nothing arrived in time; the caller keeps serving.
pub fn RawServer::accept(
  self : RawServer,
  timeout_ms? : Int = 1000,
) -> RawConn? raise WebError {
  let status = web_wait(self.socket, 0, timeout_ms)
  if status == -2 {
    return None
  }
  guard status == 0 else { raise ServeFailure(web_socket_error(self.socket)) }
  let client = web_socket_new()
  let accepted = web_accept(self.socket, client)
  if accepted == -2 {
    // The backlog emptied between wait and accept.
    web_socket_close(client)
    return None
  }
  guard accepted == 0 else {
    let code = web_socket_error(client)
    web_socket_close(client)
    raise ServeFailure(code)
  }
  Some({ socket: client, })
}

///|
/// Wait until the connection is readable (`writing` false) or writable.
/// Returns false on timeout, raises on socket errors.
pub fn RawConn::wait(
  self : RawConn,
  writing? : Bool = false,
  timeout_ms? : Int = 2000,
) -> Bool raise WebError {
  let status = web_wait(self.socket, if writing { 1 } else { 0 }, timeout_ms)
  if status == 0 {
    return true
  }
  if status == -2 {
    return false
  }
  raise ServeFailure(web_socket_error(self.socket))
}

///|
/// One receive into `buffer[offset, offset + capacity)`; returns the
/// number of bytes read, 0 on orderly close or would-block (call `wait`
/// first), and raises on socket errors. Invalid offset/capacity ranges raise
/// ServeFailure(-1) before entering the C bridge.
pub fn RawConn::recv(
  self : RawConn,
  buffer : FixedArray[Byte],
  offset? : Int = 0,
  capacity? : Int,
) -> Int raise WebError {
  guard offset >= 0 && offset <= buffer.length() else { raise ServeFailure(-1) }
  let cap = match capacity {
    Some(cap) => cap
    None => buffer.length() - offset
  }
  guard cap >= 0 && cap <= buffer.length() - offset else {
    raise ServeFailure(-1)
  }
  if cap == 0 {
    return 0
  }
  let target = if offset == 0 { buffer } else { FixedArray::make(cap, b'\x00') }
  let n = web_recv(self.socket, target, cap)
  if n > 0 {
    if offset != 0 {
      for i in 0..<n {
        buffer[offset + i] = target[i]
      }
    }
    return n
  }
  if n == 0 || n == -2 {
    return 0
  }
  raise ServeFailure(web_socket_error(self.socket))
}

///|
/// Send everything; the C bridge loops internally on would-block.
pub fn RawConn::write(self : RawConn, bytes : Bytes) -> Unit raise WebError {
  guard web_send(self.socket, bytes, bytes.length()) >= 0 else {
    raise ServeFailure(web_socket_error(self.socket))
  }
}

///|
pub fn RawConn::close(self : RawConn) -> Unit {
  web_socket_close(self.socket)
}
