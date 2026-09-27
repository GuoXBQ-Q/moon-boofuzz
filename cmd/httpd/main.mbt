// SPDX-License-Identifier: GPL-2.0-only
// httpd: a small strict HTTP fuzz target. Listens on the loopback, parses
// each request with the strict rules in http.mbt, answers malformed input
// with explicit statuses, and never lets one bad connection take the
// process down. Pair it with cmd/boofuzz run --target-cmd or drive it by
// hand; see docs/HTTPD.md.

///|
extern "c" fn exit_process(code : Int) -> Unit = "exit"

///|
suberror HttpdArgError {
  HttpdArg(String)
} derive(Debug)

///|
pub extend HttpdArgError with @moonbitlang/core/debug.Debug::{to_repr}

///|
struct HttpdConfig {
  port : Int
  max_head : Int
  max_body : Int
} derive(Debug)

///|
fn httpd_usage() -> String {
  "httpd [--port N] [--max-head N] [--max-body N]\n  --port N        loopback port to bind (default 9000, 0 = pick a free port)\n  --max-head N    head cap in bytes, 431 beyond it (default 8192)\n  --max-body N    body cap in bytes, 413 beyond it (default 1048576)"
}

///|
/// Digit-only flag values, parsed without allocation or overflow: the
/// accumulator is checked against the per-flag cap on every digit.
fn parse_flag(
  args : Array[String],
  index : Int,
  flag : String,
  cap : Int,
) -> Int raise HttpdArgError {
  guard index + 1 < args.length() else {
    raise HttpdArg("missing value for \{flag}")
  }
  let text = args[index + 1]
  guard text.length() > 0 else {
    raise HttpdArg("\{flag} expects a non-negative integer")
  }
  let mut value = 0
  for ch in text {
    guard ch is ('0'..='9') else {
      raise HttpdArg("\{flag} expects a non-negative integer, got \"\{text}\"")
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    guard value <= cap else { raise HttpdArg("\{flag} is capped at \{cap}") }
  }
  value
}

///|
const FLAG_CAP : Int = 67108864

///|
fn parse_args(args : Array[String]) -> HttpdConfig raise HttpdArgError {
  let mut port = 9000
  let mut max_head = DEFAULT_HEAD_CAP
  let mut max_body = DEFAULT_BODY_CAP
  let mut index = 0
  while index < args.length() {
    match args[index] {
      "--port" => port = parse_flag(args, index, "--port", 65535)
      "--max-head" => {
        max_head = parse_flag(args, index, "--max-head", FLAG_CAP)
        guard max_head >= 16 else {
          raise HttpdArg("--max-head must be at least 16")
        }
      }
      "--max-body" => max_body = parse_flag(args, index, "--max-body", FLAG_CAP)
      "--help" | "-h" => {
        println(httpd_usage())
        exit_process(0)
      }
      other => raise HttpdArg("unknown argument \"\{other}\"; see --help")
    }
    index += 2
  }
  { port, max_head, max_body, }
}

///|
fn main {
  let config = match load_config() {
    Some(config) => config
    None => return
  }
  let server = match open_server(config) {
    Some(server) => server
    None => return
  }
  println("httpd listening on 127.0.0.1:\{server.port()}")
  println("httpd caps: max-head=\{config.max_head} max-body=\{config.max_body}")
  for ;; {
    serve_once(server, config)
  }
}

///|
fn load_config() -> HttpdConfig? {
  let config = parse_args(@env.args()[1:].to_owned()) catch {
    HttpdArg(message) => {
      println("httpd: \{message}")
      println(httpd_usage())
      exit_process(2)
      return None
    }
  }
  Some(config)
}

///|
fn open_server(config : HttpdConfig) -> @web.RawServer? {
  let server = @web.RawServer::bind(port=config.port) catch {
    BindFailure(code) => {
      println("httpd: cannot bind port \{config.port} (code \{code})")
      exit_process(2)
      return None
    }
    ServeFailure(code) => {
      println("httpd: socket failure while binding (code \{code})")
      exit_process(2)
      return None
    }
  }
  Some(server)
}

///|
/// Accept and handle at most one connection; errors and timeouts are
/// contained so the target keeps serving the next case.
fn serve_once(server : @web.RawServer, config : HttpdConfig) -> Unit {
  let pending = server.accept(timeout_ms=1000) catch { _ => return }
  let conn = match pending {
    Some(conn) => conn
    None => return
  }
  serve_conn(conn, config)
}

///|
fn serve_conn(conn : @web.RawConn, config : HttpdConfig) -> Unit {
  let result = read_request(
    conn,
    max_head=config.max_head,
    max_body=config.max_body,
  ) catch {
    _ => {
      conn.close()
      return
    }
  }
  let outcome : String = match result {
    Parsed(request) => {
      let response = request.route()
      let omit = request.verb == "HEAD"
      conn.write(response.render(omit_body=omit)) catch {
        _ => {
          conn.close()
          return
        }
      }
      "[\{request.verb}] \{request.target} -> \{response.status}"
    }
    Rejected(reject) => {
      let response = reject.reject_response()
      conn.write(response.render()) catch {
        _ => {
          conn.close()
          return
        }
      }
      "rejected -> \{response.status}"
    }
    Closed => "closed"
  }
  println("[httpd] \{outcome}")
  discard_pending(conn)
  conn.close()
}

///|
/// Consume any unread request bytes before closing. On Windows a close
/// with unread data sends RST, which would discard the response we just
/// wrote; a lingering close keeps every answer observable.
fn discard_pending(conn : @web.RawConn) -> Unit {
  let scratch : FixedArray[Byte] = FixedArray::make(4096, b'\x00')
  for ;; {
    let pending = conn.wait(timeout_ms=200) catch { _ => return }
    guard pending else { return }
    let n = conn.recv(scratch) catch { _ => return }
    if n == 0 {
      return
    }
  }
}
