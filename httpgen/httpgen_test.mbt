// SPDX-License-Identifier: GPL-2.0-only
// Blackbox tests for HTTP message parsing and definition conversion.

///|
fn sel(
  id : String,
  primitive : @httpgen.FieldPrimitive,
  candidates : Array[String],
) -> @httpgen.FieldSelection {
  {
    id,
    primitive,
    width: 32,
    endian: "little",
    max_len: 16,
    max_mutations: 25,
    candidates,
  }
}

///|
test "parse splits request line, headers and body" {
  let message = @httpgen.HttpMessage::parse(
    "GET /index.html HTTP/1.1\r\nHost: example.com\r\nX-Token: abc\r\n\r\npayload",
  )
  assert_eq(message.verb, "GET")
  assert_eq(message.uri, "/index.html")
  assert_eq(message.version, "HTTP/1.1")
  assert_eq(message.headers.length(), 2)
  assert_eq(message.headers[0].name, "Host")
  assert_eq(message.headers[0].gap, " ")
  assert_eq(message.headers[0].value, "example.com")
  assert_eq(message.headers[1].name, "X-Token")
  assert_eq(message.headers[1].value, "abc")
  assert_true(message.has_body)
  assert_eq(message.body, "payload")
  assert_eq(message.eol, "\r\n")
  assert_eq(message.terminator, Some("\r\n\r\n"))
}

///|
test "parse accepts bare-LF line endings" {
  let message = @httpgen.HttpMessage::parse("POST /a HTTP/1.0\nHost: h\n\nb")
  assert_eq(message.eol, "\n")
  assert_eq(message.terminator, Some("\n\n"))
  assert_eq(message.headers.length(), 1)
  assert_eq(message.body, "b")
}

///|
test "parse keeps an empty terminated body and detects absence" {
  let terminated = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\n\r\n")
  assert_true(terminated.has_body)
  assert_eq(terminated.body, "")
  assert_eq(terminated.headers.length(), 0)
  let unterminated = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h")
  assert_false(unterminated.has_body)
  assert_eq(unterminated.terminator, None)
  assert_false(unterminated.final_eol)
  let trailing = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h\r\n")
  assert_false(trailing.has_body)
  assert_true(trailing.final_eol)
}

///|
test "parse errors" {
  let cases = [
    "", "GET /", "GET  / HTTP/1.1", "GET / HTTP/1.1\r\nno-colon-line", "GET / HTTP/1.1\r\n: value",
    " / HTTP/1.1\r\n",
  ]
  for text in cases {
    let failed = try {
      ignore(@httpgen.HttpMessage::parse(text))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "parse rejects oversized input" {
  let huge = "GET /" + "a".repeat(70000)
  let failed = try {
    ignore(@httpgen.HttpMessage::parse(huge))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "segments list every fuzzable part in wire order" {
  let message = @httpgen.HttpMessage::parse(
    "POST /p HTTP/1.1\r\nHost: h\r\n\r\nbody",
  )
  let segments = message.segments()
  assert_eq(segments.length(), 5)
  assert_eq(segments[0].id, "method")
  assert_eq(segments[1].id, "uri")
  assert_eq(segments[2].id, "version")
  assert_eq(segments[3].id, "hdr_0")
  assert_eq(segments[3].label, "Header Host")
  assert_eq(segments[4].id, "body")
  assert_eq(message.valid_id("hdr_0"), true)
  assert_eq(message.valid_id("hdr_1"), false)
  assert_eq(message.valid_id("body"), true)
  assert_eq(message.valid_id("nope"), false)
}

///|
test "header lookup is case-insensitive" {
  let message = @httpgen.HttpMessage::parse(
    "GET / HTTP/1.1\r\nContent-Length: 5\r\n\r\n",
  )
  assert_eq(message.header("content-length"), Some("5"))
  assert_eq(message.header("Content-Length"), Some("5"))
  assert_eq(message.header("Missing"), None)
}

///|
fn options() -> @httpgen.ConvertOptions {
  {
    request_name: "request",
    host: "127.0.0.1",
    port: 9000,
    policy_kind: "until",
    fixed_length: 0,
    case_limit: 100,
  }
}

///|
test "frozen conversion reproduces the original bytes" {
  let original = "GET /index.html HTTP/1.1\r\nHost: h\r\nUser-Agent: a\r\n\r\nbody"
  let message = @httpgen.HttpMessage::parse(original)
  // Selecting the URI with a candidate equal to the original value makes
  // case 0 render the full original message byte for byte.
  let result = @httpgen.to_definition(
    message,
    [sel("uri", Candidates, ["/index.html"])],
    options(),
  )
  assert_eq(result.previews.length(), 1)
  assert_eq(result.previews[0], @utf8.encode(original))
}

///|
test "frozen conversion without selections has zero cases" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h")
  let result = @httpgen.to_definition(message, [], options())
  assert_eq(result.case_count, 0)
  assert_eq(result.previews.length(), 0)
  assert_true(result.definition_text.contains("\"fuzzable\":false"))
  assert_false(result.definition_text.contains("\"fuzzable\":true"))
}

///|
test "automatic text mutation produces string-library cases" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h\r\n\r\n")
  let result = @httpgen.to_definition(
    message,
    [sel("uri", Text, [])],
    options(),
  )
  assert_true(result.case_count > 0)
  assert_eq(result.previews.length(), 3)
  for preview in result.previews {
    let text = @utf8.decode_lossy(preview)
    assert_true(text.has_prefix("GET "))
    assert_true(text.contains(" HTTP/1.1\r\n"))
  }
  assert_true(result.definition_text.contains("\"type\":\"text\""))
}

///|
test "explicit candidates replace method and body" {
  let message = @httpgen.HttpMessage::parse(
    "POST /x HTTP/1.1\r\nHost: h\r\n\r\na=1",
  )
  let result = @httpgen.to_definition(
    message,
    [
      sel("method", Candidates, ["PUT", "BREW"]),
      sel("body", Candidates, ["zz"]),
    ],
    options(),
  )
  assert_eq(result.case_count, 3)
  assert_eq(
    result.previews[0],
    @utf8.encode("PUT /x HTTP/1.1\r\nHost: h\r\n\r\na=1"),
  )
  assert_eq(
    result.previews[1],
    @utf8.encode("BREW /x HTTP/1.1\r\nHost: h\r\n\r\na=1"),
  )
  assert_eq(
    result.previews[2],
    @utf8.encode("POST /x HTTP/1.1\r\nHost: h\r\n\r\nzz"),
  )
}

///|
test "builtin method candidates exclude the original" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h")
  let result = @httpgen.to_definition(
    message,
    [sel("method", Candidates, [])],
    options(),
  )
  // Nine builtin methods after removing GET.
  assert_eq(result.case_count, 9)
  assert_eq(result.previews[0], @utf8.encode("POST / HTTP/1.1\r\nHost: h"))
}

///|
test "candidates without values fall back to the string library" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h")
  let result = @httpgen.to_definition(
    message,
    [sel("uri", Candidates, [])],
    options(),
  )
  assert_true(result.case_count > 0)
  assert_true(result.definition_text.contains("\"type\":\"text\""))
  assert_false(
    result.definition_text.contains("\"type\":\"simple\",\"name\":\"uri\""),
  )
}

///|
test "integer primitive uses numeric boundaries" {
  let message = @httpgen.HttpMessage::parse(
    "GET / HTTP/1.1\r\nContent-Length: 16\r\n\r\n",
  )
  let result = @httpgen.to_definition(
    message,
    [{ ..sel("hdr_0", Integer, []), width: 16, endian: "big", }],
    options(),
  )
  assert_true(result.case_count > 0)
  assert_true(result.definition_text.contains("\"type\":\"integer\""))
  // The numeric original becomes the integer default value.
  assert_true(result.definition_text.contains("\"value\":\"16\""))
  assert_true(result.definition_text.contains("\"width\":16"))
  assert_true(result.definition_text.contains("\"endian\":\"big\""))
}

///|
test "integer default falls back to zero for non-numeric values" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h")
  let result = @httpgen.to_definition(
    message,
    [sel("uri", Integer, [])],
    options(),
  )
  assert_true(result.definition_text.contains("\"value\":\"0\""))
}

///|
test "integer primitive validates width and endian" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h")
  let bad_width = try {
    ignore(
      @httpgen.to_definition(
        message,
        [{ ..sel("uri", Integer, []), width: 12, }],
        options(),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(bad_width)
  let bad_endian = try {
    ignore(
      @httpgen.to_definition(
        message,
        [{ ..sel("uri", Integer, []), endian: "middle", }],
        options(),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(bad_endian)
}

///|
test "bytes primitive emits a binary field with max_len" {
  let message = @httpgen.HttpMessage::parse(
    "POST / HTTP/1.1\r\nHost: h\r\n\r\ndata",
  )
  let result = @httpgen.to_definition(
    message,
    [{ ..sel("body", Bytes, []), max_len: 64, }],
    options(),
  )
  assert_true(result.case_count > 0)
  assert_true(result.definition_text.contains("\"type\":\"bytes\""))
  assert_true(result.definition_text.contains("\"max_len\":64"))
  let too_short = try {
    ignore(
      @httpgen.to_definition(
        message,
        [{ ..sel("body", Bytes, []), max_len: 0, }],
        options(),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(too_short)
}

///|
test "random primitive carries length and count" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h")
  let result = @httpgen.to_definition(
    message,
    [{ ..sel("uri", RandomData, []), max_len: 32, max_mutations: 7, }],
    options(),
  )
  assert_eq(result.case_count, 7)
  assert_true(result.definition_text.contains("\"type\":\"random\""))
  assert_true(result.definition_text.contains("\"max_length\":32"))
  assert_true(result.definition_text.contains("\"max_mutations\":7"))
  let zero = try {
    ignore(
      @httpgen.to_definition(
        message,
        [{ ..sel("uri", RandomData, []), max_mutations: 0, }],
        options(),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(zero)
}

///|
test "header value without a gap stays byte-exact" {
  let original = "GET / HTTP/1.1\r\nX-A:1\r\nHost: h"
  let message = @httpgen.HttpMessage::parse(original)
  let result = @httpgen.to_definition(
    message,
    [sel("hdr_0", Candidates, ["2"])],
    options(),
  )
  assert_eq(
    result.previews[0],
    @utf8.encode("GET / HTTP/1.1\r\nX-A:2\r\nHost: h"),
  )
}

///|
test "bare-LF messages round-trip byte-exactly" {
  let original = "PUT /l HTTP/1.0\nHost: h\n\nb"
  let message = @httpgen.HttpMessage::parse(original)
  let result = @httpgen.to_definition(
    message,
    [sel("uri", Candidates, ["/l"])],
    options(),
  )
  assert_eq(result.previews[0], @utf8.encode(original))
}

///|
test "execution block carries endpoint and policy" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h")
  let result = @httpgen.to_definition(message, [], options())
  assert_true(result.definition_text.contains("\"transport\":\"tcp\""))
  assert_true(result.definition_text.contains("\"port\":9000"))
  assert_true(result.definition_text.contains("\"delimiter_hex\":\"0d0a0d0a\""))
  assert_true(
    result.definition_text.contains("\"request\":{\"kind\":\"until\""),
  )
  let fixed = @httpgen.to_definition(message, [], {
    ..options(),
    policy_kind: "fixed",
    fixed_length: 7,
  })
  assert_true(fixed.definition_text.contains("\"kind\":\"fixed\",\"length\":7"))
}

///|
test "invalid selections and options are rejected" {
  let message = @httpgen.HttpMessage::parse("GET / HTTP/1.1\r\nHost: h\r\n\r\n")
  let failed = try {
    ignore(@httpgen.to_definition(message, [sel("nope", Text, [])], options()))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let duplicated = try {
    ignore(
      @httpgen.to_definition(
        message,
        [sel("uri", Text, []), sel("uri", Text, [])],
        options(),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(duplicated)
  let bad_port = try {
    ignore(@httpgen.to_definition(message, [], { ..options(), port: 0, }))
    false
  } catch {
    _ => true
  }
  assert_true(bad_port)
  let bad_policy = try {
    ignore(
      @httpgen.to_definition(message, [], {
        ..options(),
        policy_kind: "datagram",
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(bad_policy)
}
