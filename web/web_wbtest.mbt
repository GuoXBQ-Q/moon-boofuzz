// SPDX-License-Identifier: GPL-2.0-only
// Loopback HTTP tests: bind, request the upstream routes through a real
// socket, assert the JSON payloads and the pause toggle round trip.

///|
fn fake_case(index : Int) -> @db.DbCase {
  {
    name: "udp_request",
    index,
    timestamp: "2026-09-16T09:00:00",
    steps: [
      {
        step_type: "step",
        description: "udp_request",
        data: b"",
        timestamp: "",
        truncated: false,
      },
      {
        step_type: "send",
        description: "",
        data: b"\x00\xff",
        timestamp: "2026-09-16T09:00:00",
        truncated: false,
      },
      {
        step_type: "fail",
        description: "ReceiveTimedOut",
        data: b"",
        timestamp: "",
        truncated: false,
      },
    ],
  }
}

///|
/// A SessionView over two fixed cases with a pausable flag.
struct FakeSession {
  paused : @ref.Ref[Bool]
}

///|
pub impl SessionView for FakeSession with fn is_paused(self) {
  self.paused.val
}

///|
pub impl SessionView for FakeSession with fn toggle_pause(self) {
  self.paused.val = !self.paused.val
}

///|
pub impl SessionView for FakeSession with fn current_index(_self) {
  2
}

///|
pub impl SessionView for FakeSession with fn num_mutations(_self) {
  None
}

///|
pub impl SessionView for FakeSession with fn current_element(_self) {
  "[N/A]"
}

///|
pub impl SessionView for FakeSession with fn current_case_name(_self) {
  ""
}

///|
pub impl SessionView for FakeSession with fn state(_self) {
  "finished"
}

///|
pub impl SessionView for FakeSession with fn runtime_seconds(_self) {
  0.0
}

///|
pub impl SessionView for FakeSession with fn exec_speed(_self) {
  0.0
}

///|
pub impl SessionView for FakeSession with fn crashes(_self) {
  let map : Map[Int, Array[String]] = Map([])
  map[1] = ["ReceiveTimedOut"]
  map
}

///|
pub impl SessionView for FakeSession with fn test_case_data(_self, index) {
  match index {
    0 => fake_case(0)
    1 => fake_case(1)
    _ => raise @db.NoSuchCase(index)
  }
}

///|
/// Connect and send one GET without reading, so the single-threaded test
/// can serve the request before draining the response.
#borrow(socket)
extern "c" fn web_connect(socket : WebSocket, port : Int) -> Int = "bf_web_connect"

///|
fn open_request(port : Int, path : String) -> WebSocket raise {
  let client = web_socket_new()
  guard web_connect(client, port) == 0 else {
    web_socket_close(client)
    fail("client connect failed")
  }
  let payload = @utf8.encode(
    "GET " + path + " HTTP/1.1\r\nHost: localhost\r\n\r\n",
  )
  ignore(web_send(client, payload, payload.length()))
  client
}

///|
fn drain(client : WebSocket) -> String {
  let buffer : FixedArray[Byte] = FixedArray::make(16384, b'\x00')
  let mut total = 0
  for ;; {
    // Bounded waits everywhere: a missing response fails the test instead
    // of hanging it (accept queues can lag a completed loopback connect).
    guard web_wait(client, 0, 2000) == 0 else { break }
    let n = web_recv(client, buffer, 16384 - total)
    if n > 0 {
      total += n
      if total >= 16384 {
        break
      }
    } else if n >= 0 {
      break
    } else if web_socket_error(client) != 0 {
      break
    }
  }
  let body = @utf8.decode_lossy(Bytes::makei(total, i => buffer[i]))
  web_socket_close(client)
  body
}

///|
fn serve_one(server : HttpServer, view : FakeSession) -> String raise {
  let mut response = ""
  for ;; {
    match
      server.poll(request => {
        let served = handle_request(view, request)
        response = served.to_response_text()
        served
      }) {
      Some(_) => return response
      None => continue
    }
  }
}

///|
fn roundtrip(
  server : HttpServer,
  view : FakeSession,
  path : String,
) -> String raise {
  let client = open_request(server.port(), path)
  ignore(serve_one(server, view))
  drain(client)
}

///|
fn HttpResponse::to_response_text(self : HttpResponse) -> String {
  let head = "HTTP/1.1 \{self.status}\r\nContent-Type: \{self.content_type}\r\nContent-Length: \{self.body.length()}\r\nConnection: close\r\n\r\n"
  head + @utf8.decode_lossy(self.body)
}

///|
test "HTTP loopback serves the upstream routes" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  assert_true(server.port() > 0)
  let view : FakeSession = { paused: @ref.Ref(false), }
  // /api/current-run carries the upstream session_info shape.
  let body = roundtrip(server, view, "/api/current-run")
  assert_true(body.contains("\"session_info\""))
  assert_true(body.contains("\"current_index\":2"))
  assert_true(body.contains("\"is_paused\":false"))
  assert_true(body.contains("\"num_mutations\":null"))
  assert_true(
    body.contains("\"crashes\":[{\"key\":1,\"reasons\":[\"ReceiveTimedOut\"]"),
  )
  // /api/test-case/<index> returns the css/log line list.
  let case_json = roundtrip(server, view, "/api/test-case/1")
  assert_true(case_json.contains("\"index\":1"))
  assert_true(case_json.contains("\"css_class\":\"log-case\""))
  assert_true(case_json.contains("\"css_class\":\"log-fail\""))
  assert_true(case_json.contains("Check Failed: ReceiveTimedOut"))
  // Unknown case -> null log_data.
  let missing = roundtrip(server, view, "/api/test-case/99")
  assert_true(missing.contains("\"log_data\":null"))
}

///|
test "togglepause flips the flag and redirects" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let view : FakeSession = { paused: @ref.Ref(false), }
  let redirect = roundtrip(server, view, "/togglepause")
  assert_true(SessionView::is_paused(view))
  assert_true(redirect.has_prefix("HTTP/1.1 302"))
  assert_true(redirect.contains("Location: /"))
  ignore(roundtrip(server, view, "/togglepause"))
  assert_true(!SessionView::is_paused(view))
}

///|
test "index and test-case pages render; unknown paths 404" {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let view : FakeSession = { paused: @ref.Ref(false), }
  let index_page = roundtrip(server, view, "/")
  assert_true(index_page.has_prefix("HTTP/1.1 200"))
  assert_true(index_page.contains("boofuzz Fuzz Control"))
  assert_true(index_page.contains("/togglepause"))
  assert_true(index_page.contains("<a href=\"/test-case/1\">1</a>"))
  // num_mutations is unknown here: the bar is empty and the total reads "many".
  assert_true(index_page.contains(">many<"))
  assert_true(index_page.contains("0.000%"))
  let case_page = roundtrip(server, view, "/test-case/0")
  assert_true(case_page.contains("boofuzz Test Case 0"))
  assert_true(case_page.contains("Check Failed: ReceiveTimedOut"))
  assert_true(case_page.contains("Transmitted 2 bytes"))
  let missing = roundtrip(server, view, "/test-case/99")
  assert_true(missing.has_prefix("HTTP/1.1 404"))
  let unknown = roundtrip(server, view, "/nope")
  assert_true(unknown.has_prefix("HTTP/1.1 404"))
}

///|
test "bind advances past an occupied port" {
  let first = HttpServer::bind(port=0)
  defer web_socket_close(first.socket)
  let second = HttpServer::bind(port=first.port())
  defer web_socket_close(second.socket)
  assert_true(second.port() > first.port())
}

///|
fn jsonl_record(
  ordinal : Int,
  outcome : String,
  detail : String,
) -> @records.CaseRecord {
  let connect_failed = outcome == "connect_failed"
  {
    format_version: 1,
    case_id: "case-\{ordinal}",
    generator_version: "v1",
    request_name: "udp_request",
    field_path: "udp_request",
    mutation_index: ordinal,
    ordinal,
    path: ["udp_request"],
    config: { "kind": "none" },
    steps: if connect_failed {
      []
    } else {
      [
        {
          request_name: "udp_request",
          sent: b"\xaa",
          received: b"",
          completed: outcome == "passed",
        },
      ]
    },
    outcome,
    detail,
    failed_step: if outcome == "passed" {
      None
    } else if connect_failed {
      Some(-1)
    } else {
      Some(0)
    },
  }
}

///|
test "OfflineSession serves JSONL and SQLite views" {
  // JSONL backend.
  let jsonl_path = @db.temp_path()
  defer @db.remove_file(jsonl_path)
  @recordio.write_file_raw(
    jsonl_path,
    @utf8.encode(
      jsonl_record(0, "passed", "Passed").encode() +
      "\n" +
      jsonl_record(1, "receive_failed", "ReceiveTimedOut").encode() +
      "\n",
    ),
  )
  let jsonl_view = OfflineSession::open_jsonl(jsonl_path)
  defer jsonl_view.close()
  let jsonl_index = roundtrip_view(jsonl_view, "/api/current-run")
  assert_true(jsonl_index.contains("\"current_index\":2"))
  assert_true(jsonl_index.contains("\"reasons\":[\"ReceiveTimedOut\"]"))
  let jsonl_case = roundtrip_view(jsonl_view, "/test-case/1")
  assert_true(jsonl_case.contains("boofuzz Test Case 1"))
  assert_true(jsonl_case.contains("Transmitted 1 bytes"))
  // Connection errors log type "error": absent from the failure map.
  let jsonl_conn = roundtrip_view(jsonl_view, "/api/test-case/2")
  assert_true(jsonl_conn.contains("\"log_data\":null"))
  // SQLite backend: write with the logger, read back through the view.
  let db_path = @db.temp_path()
  defer @db.remove_file(db_path)
  let logger = @db.DbLogger::open(db_path)
  logger.log_record(jsonl_record(0, "passed", "Passed"))
  logger.log_record(jsonl_record(1, "receive_failed", "ReceiveTimedOut"))
  logger.close_test()
  logger.close()
  let db_view = OfflineSession::open_database(db_path)
  defer db_view.close()
  let db_api = roundtrip_view(db_view, "/api/current-run")
  assert_true(db_api.contains("\"current_index\":2"))
  assert_true(db_api.contains("\"reasons\":[\"ReceiveTimedOut\""))
  let db_page = roundtrip_view(db_view, "/")
  assert_true(db_page.contains("<a href=\"/test-case/1\">1</a>"))
}

///|
fn roundtrip_view(view : &SessionView, path : String) -> String raise {
  let server = HttpServer::bind(port=0)
  defer web_socket_close(server.socket)
  let client = open_request(server.port(), path)
  // The loopback accept queue can lag a completed connect: spin until
  // the request is actually served.
  for ;; {
    match server.poll(request => handle_request(view, request)) {
      Some(_) => break
      None => continue
    }
  }
  drain(client)
}

///|
test "LiveSession observes cases and gates on pause" {
  let ui = WebUi::open(port=0, limit=10)
  defer web_socket_close(ui.server.socket)
  let session = ui.session()
  SessionView::toggle_pause(session)
  // A paused gate still returns after the flag flips externally.
  SessionView::toggle_pause(session)
  ui.gate()
  ui.session().observe(jsonl_record(0, "passed", "Passed"))
  ui.session().observe(jsonl_record(1, "send_failed", "SendTimedOut"))
  let page = roundtrip_view(session, "/api/current-run")
  assert_true(page.contains("\"current_index\":2"))
  assert_true(page.contains("\"num_mutations\":10"))
  assert_true(page.contains("\"is_paused\":false"))
  assert_true(page.contains("\"current_test_case_name\":\"udp_request\""))
  assert_true(page.contains("\"reasons\":[\"SendTimedOut\"]"))
}
