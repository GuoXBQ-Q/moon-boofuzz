// SPDX-License-Identifier: GPL-2.0-only
// Strict-parser unit tests plus real loopback integration tests. The
// client side reuses the loopback bridge in web/http.c through extern
// declarations, mirroring web/web_wbtest.mbt.

///|
type RawSock

///|
extern "c" fn raw_socket_new() -> RawSock = "bf_web_new"

///|
#borrow(sock)
extern "c" fn raw_socket_close(sock : RawSock) -> Unit = "bf_web_close"

///|
#borrow(sock)
extern "c" fn raw_connect(sock : RawSock, port : Int) -> Int = "bf_web_connect"

///|
#borrow(sock, bytes)
extern "c" fn raw_send(sock : RawSock, bytes : Bytes, length : Int) -> Int = "bf_web_send"

///|
#borrow(sock, buffer)
extern "c" fn raw_recv(
  sock : RawSock,
  buffer : FixedArray[Byte],
  length : Int,
) -> Int = "bf_web_recv"

///|
#borrow(sock)
extern "c" fn raw_wait(sock : RawSock, writing : Int, timeout_ms : Int) -> Int = "bf_web_wait"

///|
const TEST_MAX_BODY : Int = 1024

///|
/// Parse the head of a full request text (terminator included).
fn parse_text(
  text : String,
  max_body? : Int = TEST_MAX_BODY,
) -> HeadFields raise RequestReject {
  let bytes = @utf8.encode(text)
  let buffer : FixedArray[Byte] = FixedArray::make(bytes.length(), b'\x00')
  for i in 0..<bytes.length() {
    buffer[i] = bytes[i]
  }
  match head_terminator_at(buffer, bytes.length()) {
    Some(index) => parse_head(buffer, index, max_body)
    None => raise BadRequest("test helper needs a CRLFCRLF terminator")
  }
}

///|
test "minimal GET parses with no content length" {
  let head = parse_text("GET / HTTP/1.1\r\nHost: a\r\n\r\n")
  inspect(head.verb, content="GET")
  inspect(head.target, content="/")
  inspect(head.version, content="HTTP/1.1")
  inspect(head.content_length, content="0")
  inspect(head.headers.length(), content="1")
  let (name, value) = head.headers[0]
  inspect(name, content="host")
  inspect(value, content="a")
}

///|
test "bare LF line endings are accepted" {
  let head = parse_text("GET / HTTP/1.1\nHost: a\n\n")
  inspect(head.verb, content="GET")
  inspect(head.headers.length(), content="1")
}

///|
test "duplicate identical content length is legal" {
  let head = parse_text(
    "POST /echo HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello",
  )
  inspect(head.content_length, content="5")
  inspect(head.headers.length(), content="2")
}

///|
test "rejects short request line" {
  try parse_text("GET /\r\n\r\n") catch {
    BadRequest(reason) =>
      inspect(
        reason,
        content="request line must be METHOD SP TARGET SP VERSION",
      )
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "rejects invalid verb token" {
  try parse_text("GE(T / HTTP/1.1\r\n\r\n") catch {
    BadRequest(reason) => inspect(reason, content="invalid verb token")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "rejects target without slash" {
  try parse_text("GET foo HTTP/1.1\r\n\r\n") catch {
    BadRequest(reason) =>
      inspect(reason, content="target must start with '/' or be '*'")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "rejects version without HTTP prefix" {
  try parse_text("GET / FTP/1.1\r\n\r\n") catch {
    BadRequest(reason) =>
      inspect(reason, content="version must start with HTTP/")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "rejects header without colon" {
  try parse_text("GET / HTTP/1.1\r\nHost a\r\n\r\n") catch {
    BadRequest(reason) => inspect(reason, content="header line without ':'")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "rejects invalid header name" {
  try parse_text("GET / HTTP/1.1\r\nHo(st: a\r\n\r\n") catch {
    BadRequest(reason) => inspect(reason, content="invalid header name")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "rejects non-digit content length" {
  try parse_text("GET / HTTP/1.1\r\nContent-Length: 4x\r\n\r\n") catch {
    BadRequest(reason) =>
      inspect(reason, content="Content-Length must be digits")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "rejects conflicting content length headers" {
  try
    parse_text(
      "POST /echo HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n",
    )
  catch {
    BadRequest(reason) =>
      inspect(reason, content="conflicting Content-Length headers")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "rejects content length above the cap before reading the body" {
  try
    parse_text(
      "POST /echo HTTP/1.1\r\nContent-Length: 2000\r\n\r\n",
      max_body=TEST_MAX_BODY,
    )
  catch {
    BodyTooLarge => inspect("413", content="413")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "transfer-encoding is rejected with 501" {
  try parse_text("GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") catch {
    UnsupportedTransferEncoding => inspect("501", content="501")
    _ => fail("unexpected rejection")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
fn sample_request(
  verb? : String = "GET",
  target? : String = "/",
  body? : Bytes = b"",
) -> ParsedRequest {
  ParsedRequest::{
    verb,
    target,
    version: "HTTP/1.1",
    headers: [("host", "127.0.0.1:9000"), ("x-fuzz", "seed")],
    body,
  }
}

///|
test "routes serve the index echo headers and 404" {
  inspect(sample_request().route().status, content="200")
  inspect(
    sample_request(verb="POST", target="/echo", body=b"abc").route().body,
    content="b\"abc\"",
  )
  inspect(
    sample_request(verb="POST", target="/echo").route().status,
    content="200",
  )
  inspect(
    sample_request(verb="DELETE", target="/echo").route().status,
    content="405",
  )
  inspect(sample_request(verb="POST", target="/").route().status, content="405")
  inspect(sample_request(target="/nope").route().status, content="404")
}

///|
test "render declares the exact content length and close semantics" {
  let response = sample_request().route()
  let wire = response.render()
  let text = @utf8.decode_lossy(wire)
  guard text.has_prefix("HTTP/1.1 200 OK\r\n") else {
    fail("unexpected status line")
  }
  guard text.contains("Content-Length: 15\r\n") else {
    fail("content length must match the body")
  }
  guard text.contains("Connection: close\r\n\r\n") else {
    fail("responses always close")
  }
  guard text.has_suffix("moon-httpd: ok\n") else {
    fail("body must trail the head")
  }
}

///|
test "head responses keep the declared length without the payload" {
  let response = sample_request().route()
  let wire = response.render(omit_body=true)
  let text = @utf8.decode_lossy(wire)
  guard text.contains("Content-Length: 15\r\n") else {
    fail("declared length must be kept")
  }
  guard !text.contains("moon-httpd") else { fail("payload must be omitted") }
}

///|
fn test_config(max_head? : Int = 8192) -> HttpdConfig {
  { port: 0, max_head, max_body: TEST_MAX_BODY, }
}

///|
/// Connect and send without reading, so the single-threaded test can
/// serve the request before draining the response.
fn send_raw(port : Int, payload : Bytes) -> RawSock raise {
  let client = raw_socket_new()
  guard raw_connect(client, port) == 0 else {
    raw_socket_close(client)
    fail("client connect failed")
  }
  ignore(raw_send(client, payload, payload.length()))
  client
}

///|
/// Bounded drain of everything the server sent back.
fn drain(client : RawSock) -> String {
  let buffer : FixedArray[Byte] = FixedArray::make(16384, b'\x00')
  let mut total = 0
  for ;; {
    if total == buffer.length() {
      break
    }
    guard raw_wait(client, 0, 2000) == 0 else { break }
    let n = raw_recv(client, buffer, buffer.length() - total)
    if n > 0 {
      total += n
    } else {
      break
    }
  }
  raw_socket_close(client)
  let received = Bytes::makei(total, i => buffer[i])
  @utf8.decode_lossy(received)
}

///|
fn roundtrip(
  server : @web.RawServer,
  config : HttpdConfig,
  payload : Bytes,
) -> String raise {
  let client = send_raw(server.port(), payload)
  serve_once(server, config)
  drain(client)
}

///|
test "loopback GET serves the index page" {
  let server = @web.RawServer::bind(port=0)
  let config = test_config()
  let response = roundtrip(
    server,
    config,
    @utf8.encode("GET / HTTP/1.1\r\nHost: h\r\n\r\n"),
  )
  guard response.has_prefix("HTTP/1.1 200 OK\r\n") else {
    fail("index must answer 200, got \{response}")
  }
}

///|
test "loopback garbage gets an explicit 400" {
  let server = @web.RawServer::bind(port=0)
  let config = test_config()
  let response = roundtrip(server, config, @utf8.encode("JUNKJUNK\r\n\r\n"))
  guard response.has_prefix("HTTP/1.1 400 Bad Request\r\n") else {
    fail("garbage must answer 400, got \{response}")
  }
}

///|
test "loopback echo returns the posted body" {
  let server = @web.RawServer::bind(port=0)
  let config = test_config()
  let response = roundtrip(
    server,
    config,
    @utf8.encode("POST /echo HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"),
  )
  guard response.has_prefix("HTTP/1.1 200 OK\r\n") else {
    fail("echo must answer 200, got \{response}")
  }
  guard response.has_suffix("hello") else {
    fail("echo must return the body, got \{response}")
  }
}

///|
test "loopback oversized declared body answers 413" {
  let server = @web.RawServer::bind(port=0)
  let config = test_config()
  let response = roundtrip(
    server,
    config,
    @utf8.encode("POST /echo HTTP/1.1\r\nContent-Length: 999999\r\n\r\nx"),
  )
  guard response.has_prefix("HTTP/1.1 413 Payload Too Large\r\n") else {
    fail("oversized body must answer 413, got \{response}")
  }
}

///|
test "loopback oversized head answers 431" {
  let server = @web.RawServer::bind(port=0)
  let config = test_config(max_head=16)
  let response = roundtrip(
    server,
    config,
    @utf8.encode("GET /aaaaaaaaaaaaaaaaaaaaaaaa HTTP/1.1\r\n\r\n"),
  )
  guard response.has_prefix("HTTP/1.1 431") else {
    fail("oversized head must answer 431, got \{response}")
  }
}

///|
test "loopback silent connect then close never takes the server down" {
  let server = @web.RawServer::bind(port=0)
  let config = test_config()
  let client = send_raw(server.port(), b"")
  raw_socket_close(client)
  serve_once(server, config)
  let response = roundtrip(
    server,
    config,
    @utf8.encode("GET / HTTP/1.1\r\nHost: h\r\n\r\n"),
  )
  guard response.has_prefix("HTTP/1.1 200 OK\r\n") else {
    fail("server must keep serving, got \{response}")
  }
}

///|
test "loopback LF requests use the two byte terminator for their body offset" {
  let server = @web.RawServer::bind(port=0)
  let config = test_config()
  let get = roundtrip(server, config, b"GET / HTTP/1.1\nHost: h\n\n")
  assert_true(get.has_prefix("HTTP/1.1 200 OK\r\n"))
  let echo = roundtrip(
    server, config, b"POST /echo HTTP/1.1\nContent-Length: 5\n\nhello",
  )
  assert_true(echo.has_prefix("HTTP/1.1 200 OK\r\n"))
  assert_true(echo.has_suffix("hello"))
}

///|
test "loopback body growth retains bytes from earlier reads" {
  let server = @web.RawServer::bind(port=0)
  let config : HttpdConfig = { port: 0, max_head: 64, max_body: 4096, }
  let body = "a".repeat(1024)
  let response = roundtrip(
    server,
    config,
    @utf8.encode("POST /echo HTTP/1.1\r\nContent-Length: 1024\r\n\r\n" + body),
  )
  assert_true(response.has_prefix("HTTP/1.1 200 OK\r\n"))
  assert_true(response.has_suffix(body))
}
