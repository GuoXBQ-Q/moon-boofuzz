// SPDX-License-Identifier: GPL-2.0-only
// `open FILE` — serve a read-only web view over a results file, the
// equivalent of `boofuzz open` (cli.py open_file + sessions.open_test_run
// + session_info.SessionInfo). Accepts a SQLite results database or a
// JSONL records file; serves on loopback until interrupted.

///|
const SQLITE_HEADER : Bytes = b"SQLite format 3\x00"

///|
fn open_session(path : String) -> @web.OfflineSession raise {
  let head = @recordio.read_bytes(path, max_bytes=16)
  if head == SQLITE_HEADER {
    @web.OfflineSession::open_database(path)
  } else {
    @web.OfflineSession::open_jsonl(path)
  }
}

///|
fn open_viewer(input : String, flags : ArrayView[String]) -> Unit raise {
  let opts = options(flags.to_owned(), ["--ui-port"])
  let port = int_option(opts, "--ui-port").unwrap_or(26000)
  // Port 0 asks the OS for a free port; the bound port is printed below.
  guard port >= 0 && port <= 65535 else {
    raise InvalidArguments(
      "--ui-port must be a port number (0 picks a free port)",
    )
  }
  let session = open_session(input)
  let server = @web.HttpServer::bind(port~)
  // The viewer serves until the process is interrupted; OS cleanup on
  // exit releases the socket and database handles.
  println(
    "Serving web page at http://localhost:\{server.port()}. Hit Ctrl+C to quit.",
  )
  for ;; {
    // One failed connection must not take the viewer down; report and
    // keep serving, like a long-running web app.
    let _ = try {
      server.serve_pending(request => @web.handle_request(session, request))
      true
    } catch {
      error => {
        @recordio.print_error("moon-boofuzz: \{Repr(error)}")
        false
      }
    }
    @transport.sleep_ms(20)
  }
}
