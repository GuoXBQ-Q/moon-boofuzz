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
  /// Bytes following the head, up to the declared Content-Length.
  body : Bytes
} derive(Debug, Eq)

///|
const REQUEST_LIMIT : Int = 8192

///|
const BODY_LIMIT : Int = 1048576

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
  let mut buffer : FixedArray[Byte] = FixedArray::make(REQUEST_LIMIT, b'\x00')
  let mut received = 0
  let mut head_end = -1
  let mut content_length = 0
  // Headers arrive with the first segment on loopback; wait, then drain
  // until the header terminator, then until the declared body length or
  // the caps. Each read gets a fresh 2000 ms budget.
  for ;; {
    if head_end >= 0 && received >= head_end + 4 + content_length {
      break
    }
    let status = web_wait(client, 0, 2000)
    guard status == 0 else {
      if received > 0 {
        break
      }
      raise ServeFailure(-2)
    }
    if received == buffer.length() {
      // Grow only for a declared body; otherwise the request is capped.
      let needed = head_end + 4 + content_length
      if head_end < 0 || content_length <= 0 || buffer.length() >= needed {
        break
      }
      let grown : FixedArray[Byte] = FixedArray::make(needed, b'\x00')
      for i in 0..<received {
        grown[i] = buffer[i]
      }
      buffer = grown
    }
    let n = web_recv(client, buffer, buffer.length() - received)
    if n > 0 {
      received += n
      if head_end < 0 {
        match header_end_at(buffer, received) {
          Some(index) => {
            head_end = index
            content_length = header_content_length(buffer, index)
            guard content_length <= BODY_LIMIT else { raise ServeFailure(-4) }
          }
          None =>
            // A head that fills the buffer without a terminator is
            // served as-is; only bodies may exceed REQUEST_LIMIT.
            if received >= REQUEST_LIMIT {
              break
            }
        }
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
  let body : Bytes = if head_end >= 0 {
    let start = head_end + 4
    let end = if start + content_length < received {
      start + content_length
    } else {
      received
    }
    if end > start {
      Bytes::makei(end - start, i => buffer[start + i])
    } else {
      b""
    }
  } else {
    b""
  }
  let request = parse_request_line(buffer, received)
  { verb: request.verb, path: request.path, body, }
}

///|
/// The offset of the CRLFCRLF head terminator, if fully received.
fn header_end_at(buffer : FixedArray[Byte], length : Int) -> Int? {
  if length < 4 {
    return None
  }
  let mut i = 0
  while i + 3 < length {
    if buffer[i] == b'\x0d' &&
      buffer[i + 1] == b'\x0a' &&
      buffer[i + 2] == b'\x0d' &&
      buffer[i + 3] == b'\x0a' {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// The declared Content-Length inside the head (0 when absent, malformed
/// or non-numeric). Only the first Content-Length header counts.
fn header_content_length(buffer : FixedArray[Byte], head_end : Int) -> Int {
  let head_bytes = Bytes::makei(head_end, i => buffer[i])
  let head = @utf8.decode_lossy(head_bytes)
  for raw_line in head.split("\n") {
    let line = strip_line_ending(raw_line.to_owned())
    let colon = match line.find(":") {
      Some(index) => index
      None => continue
    }
    let name = trim_ows(line[:colon].to_owned()).to_lower()
    if name == "content-length" {
      return parse_decimal(trim_ows(line[colon + 1:].to_owned()))
    }
  }
  0
}

///|
fn strip_line_ending(line : String) -> String {
  if line.length() > 0 && line[line.length() - 1] == '\r' {
    line[:line.length() - 1].to_owned()
  } else {
    line
  }
}

///|
fn trim_ows(text : String) -> String {
  let mut start = 0
  let mut end = text.length()
  while start < end && (text[start] == ' ' || text[start] == '\t') {
    start += 1
  }
  while end > start && (text[end - 1] == ' ' || text[end - 1] == '\t') {
    end -= 1
  }
  text[start:end].to_owned()
}

///|
/// Strict decimal; any other character (including a sign) yields 0.
fn parse_decimal(text : String) -> Int {
  let mut value = 0
  for ch in text {
    guard ch >= '0' && ch <= '9' else { return 0 }
    value = value * 10 + (ch.to_int() - 48)
    guard value <= BODY_LIMIT else { return BODY_LIMIT + 1 }
  }
  value
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
  { verb, path, body: b"", }
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
    400 => "Bad Request"
    404 => "Not Found"
    405 => "Method Not Allowed"
    413 => "Content Too Large"
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
