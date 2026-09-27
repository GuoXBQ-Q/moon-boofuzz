// SPDX-License-Identifier: GPL-2.0-only
// Strict HTTP/1.x request parsing and routing for the httpd fuzz target.
// Unlike the web UI server (web/server.mbt) this answers malformed input
// with an explicit status so a fuzzer can observe the difference between
// "rejected" (400/405/413/431/501) and "connection dropped".

///|
/// Why the server refused a request; each variant maps to one response
/// status and is observable by the fuzzer.
pub(all) suberror RequestReject {
  /// Malformed request line or headers (400).
  BadRequest(String)
  /// Declared Content-Length above the cap (413).
  BodyTooLarge
  /// Head terminator not seen within the head cap (431).
  HeadTooLarge
  /// Transfer-Encoding is not supported (501).
  UnsupportedTransferEncoding
} derive(Debug, Eq)

///|
pub extend RequestReject with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RequestReject with Eq::{not_equal, equal}

///|
/// A fully parsed request: request line, headers (names lowercased, in
/// arrival order) and the received body. Multiple identical
/// Content-Length headers are legal; conflicting ones reject.
pub(all) struct ParsedRequest {
  verb : String
  target : String
  version : String
  headers : Array[(String, String)]
  body : Bytes
} derive(Debug, Eq)

///|
pub extend ParsedRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ParsedRequest with Eq::{not_equal, equal}

///|
/// Result of reading one connection.
pub(all) enum ReadResult {
  /// Complete request; route and answer.
  Parsed(ParsedRequest)
  /// The request broke a strict rule; answer with the mapped status.
  Rejected(RequestReject)
  /// Nothing usable arrived (no bytes, stall, or premature close);
  /// close silently like a real server.
  Closed
} derive(Debug, Eq)

///|
pub extend ReadResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReadResult with Eq::{not_equal, equal}

///|
const DEFAULT_HEAD_CAP : Int = 8192

///|
const DEFAULT_BODY_CAP : Int = 1048576

///|
/// Read one connection up to the head terminator plus the declared body.
/// Every read gets a fresh `timeout_ms` budget; a stall with partial data
/// closes silently rather than guessing.
pub fn read_request(
  conn : @web.RawConn,
  max_head? : Int = DEFAULT_HEAD_CAP,
  max_body? : Int = DEFAULT_BODY_CAP,
  timeout_ms? : Int = 2000,
) -> ReadResult raise @web.WebError {
  let mut buffer : FixedArray[Byte] = FixedArray::make(max_head + 16, b'\x00')
  let mut received = 0
  let mut head : HeadFields? = None
  for ;; {
    match head {
      Some(fields) =>
        if received >= fields.body_start + fields.content_length {
          break
        }
      None => ()
    }
    let ready = conn.wait(timeout_ms~)
    guard ready else {
      // Timeout: with zero bytes this is a silent client, with partial
      // data a stalled peer; both close without a response.
      return Closed
    }
    if received == buffer.length() {
      match head {
        None => return Rejected(HeadTooLarge)
        Some(fields) => {
          let needed = fields.body_start + fields.content_length
          buffer = grow_buffer(buffer, received, needed)
        }
      }
    }
    let n = conn.recv(buffer, offset=received)
    if n > 0 {
      received += n
      if head is None {
        match head_terminator_at(buffer, received) {
          Some(index) => {
            let body_start = index +
              (if buffer[index] == b'\x0d' { 4 } else { 2 })
            if body_start > max_head {
              return Rejected(HeadTooLarge)
            }
            head = Some(
              parse_head(buffer, index, max_body) catch {
                reject => return Rejected(reject)
              },
            )
          }
          None => if received >= max_head { return Rejected(HeadTooLarge) }
        }
      }
    } else if n == 0 {
      // Orderly close: incomplete requests are dropped, not answered.
      return Closed
    }
  }
  let fields = match head {
    Some(fields) => fields
    None => return Closed
  }
  let start = fields.body_start
  let body = Bytes::makei(fields.content_length, i => buffer[start + i])
  Parsed(ParsedRequest::{
    verb: fields.verb,
    target: fields.target,
    version: fields.version,
    headers: fields.headers,
    body,
  })
}

///|
fn grow_buffer(
  buffer : FixedArray[Byte],
  received : Int,
  needed : Int,
) -> FixedArray[Byte] {
  let grown : FixedArray[Byte] = FixedArray::make(needed, b'\x00')
  for i in 0..<received {
    grown[i] = buffer[i]
  }
  grown
}

///|
/// The offset where the head ends: CRLFCRLF returns the offset of the
/// first CR, LFLF (and CRLFLF tails) the offset of the first LF of the
/// pair. Line endings are lenient; head structure is not.
fn head_terminator_at(buffer : FixedArray[Byte], length : Int) -> Int? {
  for i in 0..<length {
    if i + 3 < length &&
      buffer[i] == b'\x0d' &&
      buffer[i + 1] == b'\x0a' &&
      buffer[i + 2] == b'\x0d' &&
      buffer[i + 3] == b'\x0a' {
      return Some(i)
    }
    if i + 1 < length && buffer[i] == b'\x0a' && buffer[i + 1] == b'\x0a' {
      return Some(i)
    }
  }
  None
}

///|
struct HeadFields {
  verb : String
  target : String
  version : String
  headers : Array[(String, String)]
  body_start : Int
  content_length : Int
} derive(Debug, Eq)

///|
/// Strict head parser over `buffer[0, head_end)`. Line endings are
/// lenient (CRLF or LF); structure is strict: a 3-token request line,
/// token header names with no whitespace before the colon, a digit-only
/// and conflict-free Content-Length.
fn parse_head(
  buffer : FixedArray[Byte],
  head_end : Int,
  max_body : Int,
) -> HeadFields raise RequestReject {
  let head_bytes = Bytes::makei(head_end, i => buffer[i])
  let head = @utf8.decode_lossy(head_bytes)
  let raw_lines : Array[String] = []
  for raw in head.split("\n") {
    raw_lines.push(strip_cr(raw.to_owned()))
  }
  // split always yields trailing "" when the head ends with line
  // breaks; drop them, and treat any interior empty line as an error.
  let mut end_index = raw_lines.length()
  while end_index > 0 && raw_lines[end_index - 1] == "" {
    end_index -= 1
  }
  let lines : Array[String] = []
  for i in 0..<end_index {
    guard raw_lines[i] != "" else { raise BadRequest("empty header line") }
    lines.push(raw_lines[i])
  }
  guard lines.length() > 0 else { raise BadRequest("empty request") }
  let tokens = lines[0].split(" ").collect()
  guard tokens.length() == 3 else {
    raise BadRequest("request line must be METHOD SP TARGET SP VERSION")
  }
  let verb = tokens[0].to_owned()
  let target = tokens[1].to_owned()
  let version = tokens[2].to_owned()
  guard is_token(verb) else { raise BadRequest("invalid verb token") }
  guard target.length() > 0 && (target is ['/', ..] || target is "*") else {
    raise BadRequest("target must start with '/' or be '*'")
  }
  guard version.has_prefix("HTTP/") else {
    raise BadRequest("version must start with HTTP/")
  }
  let headers : Array[(String, String)] = []
  let content_lengths : Array[String] = []
  for i in 1..<lines.length() {
    let line = lines[i]
    guard line.find(":") is Some(colon) else {
      raise BadRequest("header line without ':'")
    }
    let name = line[:colon].to_owned()
    guard name.length() > 0 && is_token(name) else {
      raise BadRequest("invalid header name")
    }
    let value = trim_ows(line[colon + 1:].to_owned())
    let lowered = name.to_lower()
    headers.push((lowered, value))
    if lowered == "content-length" {
      content_lengths.push(value)
    }
    if lowered == "transfer-encoding" {
      raise UnsupportedTransferEncoding
    }
  }
  let content_length = content_length_from(content_lengths, max_body)
  let body_start = head_end + (if buffer[head_end] == b'\x0d' { 4 } else { 2 })
  { verb, target, version, headers, body_start, content_length, }
}

///|
/// Parse one Content-Length value under the cap. The running value is
/// checked against the cap on every digit, so arbitrarily long garbage
/// cannot overflow the accumulator.
fn parse_content_length(
  text : String,
  max_body : Int,
) -> Int raise RequestReject {
  guard text.length() > 0 else {
    raise BadRequest("Content-Length must be digits")
  }
  let mut value = 0
  for ch in text {
    guard ch is ('0'..='9') else {
      raise BadRequest("Content-Length must be digits")
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    guard value <= max_body else { raise BodyTooLarge }
  }
  value
}

///|
/// Zero, one or many Content-Length headers: duplicates must agree, the
/// value must fit the cap.
fn content_length_from(
  seen : Array[String],
  max_body : Int,
) -> Int raise RequestReject {
  if seen.is_empty() {
    return 0
  }
  let mut value = -1
  for text in seen {
    let parsed = parse_content_length(text, max_body)
    if value < 0 {
      value = parsed
    } else if parsed != value {
      raise BadRequest("conflicting Content-Length headers")
    }
  }
  value
}

///|
fn strip_cr(line : String) -> String {
  if line.length() > 0 && line[line.length() - 1] == '\r' {
    line[:line.length() - 1].to_owned()
  } else {
    line
  }
}

///|
fn trim_ows(text : String) -> String {
  let mut start = 0
  let end = text.length()
  while start < end && text[start] is (' ' | '\t') {
    start += 1
  }
  let mut stop = end
  while stop > start && text[stop - 1] is (' ' | '\t') {
    stop -= 1
  }
  text[start:stop].to_owned()
}

///|
/// RFC 7230 token characters: the set allowed in methods and header names.
fn is_token(text : String) -> Bool {
  if text.length() == 0 {
    return false
  }
  for ch in text {
    let ok = ch is ('a'..='z') ||
      ch is ('A'..='Z') ||
      ch is ('0'..='9') ||
      ch
      is ('!'
      | '#'
      | '$'
      | '%'
      | '&'
      | '\''
      | '*'
      | '+'
      | '-'
      | '.'
      | '^'
      | '_'
      | '`'
      | '|'
      | '~')
    if !ok {
      return false
    }
  }
  true
}

///|
/// Route a parsed request. Every response closes the connection, so the
/// fuzz model stays one request per case.
pub fn ParsedRequest::route(self : ParsedRequest) -> Response {
  if self.has_transfer_encoding() {
    return {
      status: 501,
      content_type: "text/plain",
      body: b"transfer-encoding is not supported\n",
    }
  }
  match (self.verb, self.target) {
    ("GET", "/") | ("HEAD", "/") =>
      { status: 200, content_type: "text/plain", body: b"moon-httpd: ok\n", }
    ("GET", "/echo") | ("POST", "/echo") | ("PUT", "/echo") =>
      { status: 200, content_type: self.content_type(), body: self.body, }
    (_, "/echo") =>
      {
        status: 405,
        content_type: "text/plain",
        body: b"verb not allowed; use GET, POST or PUT\n",
      }
    ("GET", "/headers") | ("HEAD", "/headers") =>
      {
        status: 200,
        content_type: "text/plain",
        body: render_headers(self.headers),
      }
    (_, "/") | (_, "/headers") =>
      {
        status: 405,
        content_type: "text/plain",
        body: b"verb not allowed; use GET or HEAD\n",
      }
    _ => { status: 404, content_type: "text/plain", body: b"not found\n", }
  }
}

///|
fn ParsedRequest::has_transfer_encoding(self : ParsedRequest) -> Bool {
  self.headers.any(pair => {
    match pair {
      (name, _) => name == "transfer-encoding"
    }
  })
}

///|
fn ParsedRequest::content_type(self : ParsedRequest) -> String {
  match self.header("content-type") {
    Some(value) => value
    None => "application/octet-stream"
  }
}

///|
pub fn ParsedRequest::header(self : ParsedRequest, name : String) -> String? {
  let wanted = name.to_lower()
  for pair in self.headers {
    let (key, value) = pair
    if key == wanted {
      return Some(value)
    }
  }
  None
}

///|
fn render_headers(headers : Array[(String, String)]) -> Bytes {
  let builder = StringBuilder()
  builder <+ "parsed headers: \{headers.length()}\n"
  for pair in headers {
    let (name, value) = pair
    builder <+ "\{name}: \{value}\n"
  }
  @utf8.encode(builder.to_string())
}

///|
/// Map a rejection to its response.
pub fn RequestReject::reject_response(self : RequestReject) -> Response {
  match self {
    BadRequest(reason) =>
      {
        status: 400,
        content_type: "text/plain",
        body: @utf8.encode("bad request: \{reason}\n"),
      }
    BodyTooLarge =>
      {
        status: 413,
        content_type: "text/plain",
        body: b"declared body above the cap\n",
      }
    HeadTooLarge =>
      {
        status: 431,
        content_type: "text/plain",
        body: b"head terminator not seen within the cap\n",
      }
    UnsupportedTransferEncoding =>
      {
        status: 501,
        content_type: "text/plain",
        body: b"transfer-encoding is not supported\n",
      }
  }
}

///|
/// The plain response record the httpd writes back.
pub(all) struct Response {
  status : Int
  content_type : String
  body : Bytes
} derive(Debug, Eq)

///|
pub extend Response with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Response with Eq::{not_equal, equal}

///|
pub fn Response::status_text(self : Response) -> String {
  match self.status {
    200 => "OK"
    400 => "Bad Request"
    404 => "Not Found"
    405 => "Method Not Allowed"
    413 => "Payload Too Large"
    431 => "Request Header Fields Too Large"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    code => "Status \{code}"
  }
}

///|
/// Render status line, headers and body. Content-Length always matches
/// the body bytes that follow; HEAD responses keep the declared length
/// but omit the payload, per RFC 7231.
pub fn Response::render(self : Response, omit_body? : Bool = false) -> Bytes {
  let builder = StringBuilder()
  builder <+ "HTTP/1.1 \{self.status} \{self.status_text()}\r\n"
  builder <+ "Content-Type: \{self.content_type}\r\n"
  builder <+ "Content-Length: \{self.body.length()}\r\n"
  builder <+ "Connection: close\r\n\r\n"
  let head = @utf8.encode(builder.to_string())
  if omit_body {
    return head
  }
  let total = head.length() + self.body.length()
  Bytes::makei(total, i => {
    if i < head.length() {
      head[i]
    } else {
      self.body[i - head.length()]
    }
  })
}
