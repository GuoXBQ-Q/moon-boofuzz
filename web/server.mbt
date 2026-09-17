// SPDX-License-Identifier: GPL-2.0-only
// Minimal HTTP/1.1 serving over the loopback bridge in web/http.c. The
// port-in-use retry mirrors sessions/session.py build_webapp_thread
// (EADDRINUSE -> port += 1). Requests are read to the end of headers,
// only the first request line is interpreted, responses close the
// connection.

///|
pub(all) suberror WebError {
  BindFailure(Int)
  ServeFailure(Int)
} derive(Debug)

///|
pub(all) struct HttpRequest {
  verb : String
  path : String
} derive(Debug, Eq)

///|
const REQUEST_LIMIT : Int = 8192

///|
pub struct HttpServer {
  socket : WebSocket
  bound_port : Int
}

///|
/// Bind the loopback web UI port, advancing by one while the address is
/// in use, and return the server plus the port actually bound.
pub fn HttpServer::bind(port~ : Int) -> HttpServer raise WebError {
  let mut candidate = port
  for _ in 0..<100 {
    let socket = web_socket_new()
    if web_socket_error(socket) != 0 {
      raise BindFailure(web_socket_error(socket))
    }
    let bound = web_listen(socket, candidate)
    if bound > 0 {
      return { socket, bound_port: bound, }
    }
    let code = web_socket_error(socket)
    web_socket_close(socket)
    // WSAEADDRINUSE = 10048 on Windows, EADDRINUSE = 98/48 elsewhere.
    if code != 10048 && code != 98 && code != 48 {
      raise BindFailure(code)
    }
    candidate += 1
  }
  raise BindFailure(0)
}

///|
pub fn HttpServer::port(self : HttpServer) -> Int {
  self.bound_port
}

///|
/// Nonblocking accept; handles at most one pending request through the
/// router, or returns None when the listen backlog is empty.
pub fn HttpServer::poll(
  self : HttpServer,
  handle : (HttpRequest) -> HttpResponse raise,
) -> HttpRequest? raise {
  let client = web_socket_new()
  let status = web_accept(self.socket, client)
  if status == -2 {
    web_socket_close(client)
    return None
  }
  if status != 0 {
    let code = web_socket_error(client)
    web_socket_close(client)
    raise ServeFailure(code)
  }
  // One bad connection (a silent port scanner, a malformed request, a peer
  // that vanished mid-read) is dropped without taking the server down:
  // upstream serves every request on its own tornado worker thread
  // (sessions/web_app.py), so a stuck client can never end the fuzz run.
  let request = read_request(client) catch {
    _ => {
      web_socket_close(client)
      return None
    }
  }
  let response = handle(request) catch { _ => HttpResponse::internal_error() }
  write_response(client, response)
  web_socket_close(client)
  Some(request)
}

///|
/// Handle every pending request through the router, then return.
pub fn HttpServer::serve_pending(
  self : HttpServer,
  handle : (HttpRequest) -> HttpResponse raise,
) -> Unit raise {
  for ;; {
    match self.poll(handle) {
      Some(_) => continue
      None => return
    }
  }
}

///|
fn read_request(client : WebSocket) -> HttpRequest raise WebError {
  let buffer : FixedArray[Byte] = FixedArray::make(REQUEST_LIMIT, b'\x00')
  let mut received = 0
  // Headers arrive with the first segment on loopback; wait, then drain
  // until the header terminator or the cap.
  for ;; {
    let status = web_wait(client, 0, 2000)
    guard status == 0 else {
      if received > 0 {
        break
      }
      raise ServeFailure(-2)
    }
    let n = web_recv(client, buffer, REQUEST_LIMIT - received)
    if n > 0 {
      received += n
      if received >= REQUEST_LIMIT || has_header_end(buffer, received) {
        break
      }
    } else if n == 0 || n == -1 {
      break
    } else {
      continue
    }
  }
  // A connection that never sent a request byte is not a GET / (an empty
  // read used to render the index page); treat it as a dropped client.
  guard received > 0 else { raise ServeFailure(-3) }
  parse_request_line(buffer, received)
}

///|
fn has_header_end(buffer : FixedArray[Byte], length : Int) -> Bool {
  let mut i = 0
  let limit = length - 3
  for ;; {
    if i >= limit {
      return false
    }
    if buffer[i] == b'\r' &&
      buffer[i + 1] == b'\n' &&
      buffer[i + 2] == b'\r' &&
      buffer[i + 3] == b'\n' {
      return true
    }
    i += 1
  }
}

///|
fn parse_request_line(
  buffer : FixedArray[Byte],
  length : Int,
) -> HttpRequest raise WebError {
  let mut end = 0
  while end < length && buffer[end] != b'\r' && buffer[end] != b'\n' {
    end += 1
  }
  // Without a usable "VERB PATH" request line the connection is garbage;
  // answering it with the index page would mask broken clients.
  guard end > 0 else { raise ServeFailure(-3) }
  let line = Bytes::makei(end, i => buffer[i])
  let text = @utf8.decode_lossy(line)
  let parts = text.split(" ").collect()
  guard parts.length() >= 2 else { raise ServeFailure(-3) }
  let verb = parts[0].to_owned()
  let raw_path = parts[1].to_owned()
  let path = match raw_path.find("?") {
    Some(index) if index > 0 => raw_path[0:index].to_owned()
    _ => raw_path
  }
  { verb, path, }
}

///|
pub(all) struct HttpResponse {
  status : Int
  content_type : String
  body : Bytes
  headers : Array[String]
} derive(Debug)

///|
pub fn HttpResponse::html(body : String) -> HttpResponse {
  {
    status: 200,
    content_type: "text/html; charset=utf-8",
    body: @utf8.encode(body),
    headers: [],
  }
}

///|
pub fn HttpResponse::json(body : String) -> HttpResponse {
  {
    status: 200,
    content_type: "application/json",
    body: @utf8.encode(body),
    headers: [],
  }
}

///|
pub fn HttpResponse::redirect(location : String) -> HttpResponse {
  {
    status: 302,
    content_type: "text/plain; charset=utf-8",
    body: b"",
    headers: ["Location: " + location],
  }
}

///|
pub fn HttpResponse::not_found() -> HttpResponse {
  {
    status: 404,
    content_type: "text/plain; charset=utf-8",
    body: @utf8.encode("404 not found"),
    headers: [],
  }
}

///|
/// The answer to a raising route handler, like Flask's default error page.
pub fn HttpResponse::internal_error() -> HttpResponse {
  {
    status: 500,
    content_type: "text/plain; charset=utf-8",
    body: @utf8.encode("500 internal server error"),
    headers: [],
  }
}

///|
fn status_text(status : Int) -> String {
  match status {
    200 => "OK"
    302 => "Found"
    404 => "Not Found"
    500 => "Internal Server Error"
    _ => "OK"
  }
}

///|
fn write_response(client : WebSocket, response : HttpResponse) -> Unit {
  let head = StringBuilder()
  head <+ "HTTP/1.1 \{response.status} \{status_text(response.status)}\r\n"
  head <+ "Content-Type: \{response.content_type}\r\n"
  head <+ "Content-Length: \{response.body.length()}\r\n"
  for header in response.headers {
    head <+ "\{header}\r\n"
  }
  head <+ "Connection: close\r\n\r\n"
  let head_bytes = @utf8.encode(head.to_string())
  ignore(web_send(client, head_bytes, head_bytes.length()))
  if response.body.length() > 0 {
    ignore(web_send(client, response.body, response.body.length()))
  }
}

///|
fn html_escape(text : String) -> String {
  text
  .replace(old="&", new="&amp;")
  .replace(old="<", new="&lt;")
  .replace(old=">", new="&gt;")
  .replace(old="\"", new="&quot;")
}
