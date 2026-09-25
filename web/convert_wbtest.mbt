// SPDX-License-Identifier: GPL-2.0-only
// Loopback tests for the converter app: POST bodies with Content-Length,
// form decoding, and the three-step paste -> pick -> generate flow.

///|
fn post_request(port : Int, path : String, body : String) -> WebSocket raise {
  let client = web_socket_new()
  guard web_connect(client, port) == 0 else {
    web_socket_close(client)
    fail("client connect failed")
  }
  // Form bodies in these tests are ASCII, so char length == byte length.
  let payload = @utf8.encode(
    "POST " +
    path +
    " HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: " +
    body.length().to_string() +
    "\r\n\r\n" +
    body,
  )
  ignore(web_send(client, payload, payload.length()))
  client
}

///|
fn serve_one_convert(server : HttpServer) -> String raise {
  let mut response = ""
  for ;; {
    match
      server.poll(request => {
        let served = handle_convert_request(request)
        response = served.to_response_text()
        served
      }) {
      Some(_) => return response
      None => continue
    }
  }
}

///|
fn post_roundtrip(
  server : HttpServer,
  path : String,
  body : String,
) -> String raise {
  let client = post_request(server.port(), path, body)
  ignore(serve_one_convert(server))
  drain(client)
}

///|
test "POST bodies are delivered through the declared Content-Length" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let client = post_request(server.port(), "/convert/segments", "a=1&b=2")
  let mut seen = ""
  for ;; {
    match
      server.poll(request => {
        let form = parse_form(request.body)
        let payload : Json = {
          "a": form.get("a").unwrap_or(""),
          "b": form.get("b").unwrap_or(""),
          "bytes": request.body.length(),
        }
        let served = HttpResponse::json(payload.stringify())
        seen = served.to_response_text()
        served
      }) {
      Some(_) => break
      None => continue
    }
  }
  assert_true(seen.has_prefix("HTTP/1.1 200"))
  assert_true(seen.contains("\"a\":\"1\""))
  assert_true(seen.contains("\"b\":\"2\""))
  ignore(drain(client))
}

///|
test "form decoding handles percent escapes and plus spaces" {
  let form = parse_form(@utf8.encode("k%20ey=n%2Bv%0D%0Alue&plain=a+b"))
  assert_eq(form.get("k ey"), Some("n+v\r\nlue"))
  assert_eq(form.get("plain"), Some("a b"))
}

///|
test "converter input page renders the paste form" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let client = open_request(server.port(), "/convert")
  ignore(serve_one_convert(server))
  let body = drain(client)
  assert_true(body.has_prefix("HTTP/1.1 200"))
  assert_true(body.contains("name=\"rawtext\""))
  assert_true(body.contains("/convert/segments"))
}

///|
test "converter segments page lists every segment" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let rawtext = "GET%20%2F%20HTTP%2F1.1%0D%0AHost%3A%20127.0.0.1%0D%0A%0D%0Ahello"
  let body = post_roundtrip(server, "/convert/segments", "rawtext=" + rawtext)
  assert_true(body.has_prefix("HTTP/1.1 200"))
  assert_true(body.contains("name=\"f_method\""))
  assert_true(body.contains("name=\"f_uri\""))
  assert_true(body.contains("name=\"f_version\""))
  assert_true(body.contains("name=\"f_hdr_0\""))
  assert_true(body.contains("name=\"f_body\""))
  assert_true(body.contains("Header Host"))
  // The raw message rides along for the stateless generate step.
  assert_true(body.contains("name=\"rawtext\""))
}

///|
test "converter rejects a malformed message with 400" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let body = post_roundtrip(server, "/convert/segments", "rawtext=nonsense")
  assert_true(body.has_prefix("HTTP/1.1 400"))
  assert_true(body.contains("Back to the converter"))
}

///|
test "converter generates a validated definition with previews" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let rawtext = "GET%20%2F%20HTTP%2F1.1%0D%0AHost%3A%20127.0.0.1%0D%0A%0D%0A"
  let form = "rawtext=" +
    rawtext +
    "&request_name=request&host=127.0.0.1&port=9000&policy=until&fixed_length=2&case_limit=100" +
    "&f_uri=on&c_uri=%2Fabc%0A%2Fdef"
  let body = post_roundtrip(server, "/convert/generate", form)
  assert_true(body.has_prefix("HTTP/1.1 200"))
  assert_true(body.contains("schema_version"))
  assert_true(body.contains("fuzzing cases"))
  // The first preview payload is the message with the first candidate URI.
  assert_true(body.contains("GET /abc HTTP/1.1\\r\\nHost: 127.0.0.1"))
  assert_true(body.contains("id=\"definition-json\""))
}

///|
test "converter generate validates numeric options" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let rawtext = "GET%20%2F%20HTTP%2F1.1%0D%0AHost%3A%20h%0D%0A%0D%0A"
  let body = post_roundtrip(
    server,
    "/convert/generate",
    "rawtext=" + rawtext + "&port=notanumber",
  )
  assert_true(body.has_prefix("HTTP/1.1 400"))
  assert_true(body.contains("port must be a decimal number"))
}

///|
test "converter serves 405 and 404" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let wrong_method = post_roundtrip(server, "/convert", "rawtext=x")
  assert_true(wrong_method.has_prefix("HTTP/1.1 405"))
  let client = open_request(server.port(), "/convert/nope")
  ignore(serve_one_convert(server))
  let missing = drain(client)
  assert_true(missing.has_prefix("HTTP/1.1 404"))
}

///|
test "segments page offers a mutation primitive per segment" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let rawtext = "GET%20%2F%20HTTP%2F1.1%0D%0AHost%3A%20h%0D%0A%0D%0A"
  let body = post_roundtrip(server, "/convert/segments", "rawtext=" + rawtext)
  assert_true(body.contains("name=\"p_uri\""))
  assert_true(body.contains("name=\"p_method\""))
  assert_true(body.contains("value=\"integer\""))
  assert_true(body.contains("value=\"candidates\""))
  // The method row defaults to candidates; other rows to the string library.
  assert_true(body.contains("candidates (built-in HTTP methods)"))
  assert_true(body.contains("params_integer_uri"))
}

///|
test "generate honors the integer primitive" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let rawtext = "GET%20%2F%20HTTP%2F1.1%0D%0AContent-Length%3A%2016%0D%0A%0D%0A"
  let form = "rawtext=" +
    rawtext +
    "&f_hdr_0=on&p_hdr_0=integer&p_hdr_0_width=16&p_hdr_0_endian=big"
  let body = post_roundtrip(server, "/convert/generate", form)
  assert_true(body.has_prefix("HTTP/1.1 200"))
  assert_true(body.contains("\"type\":\"integer\""))
  assert_true(body.contains("\"width\":16"))
  assert_true(body.contains("\"endian\":\"big\""))
}

///|
test "generate rejects an invalid primitive width" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let rawtext = "GET%20%2F%20HTTP%2F1.1%0D%0AHost%3A%20h%0D%0A%0D%0A"
  let form = "rawtext=" + rawtext + "&f_uri=on&p_uri=integer&p_uri_width=12"
  let body = post_roundtrip(server, "/convert/generate", form)
  assert_true(body.has_prefix("HTTP/1.1 400"))
  assert_true(body.contains("integer width must be 8, 16, 32 or 64"))
}

///|
test "generate honors the bytes primitive on the body" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let rawtext = "POST%20%2F%20HTTP%2F1.1%0D%0AHost%3A%20h%0D%0A%0D%0Adata"
  let form = "rawtext=" + rawtext + "&f_body=on&p_body=bytes&p_body_maxlen=64"
  let body = post_roundtrip(server, "/convert/generate", form)
  assert_true(body.has_prefix("HTTP/1.1 200"))
  assert_true(body.contains("\"type\":\"bytes\""))
  assert_true(body.contains("\"max_len\":64"))
}
