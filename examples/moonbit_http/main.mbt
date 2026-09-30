// SPDX-License-Identifier: GPL-2.0-only
// A protocol is defined entirely in MoonBit; no definition JSON is loaded.
// Offline: moon run --target native examples/moonbit_http
// Live:    moon run --target native examples/moonbit_http -- run 127.0.0.1 9000

///|
/// A small HTTP request whose method, path and X-Fuzz value are the only
/// mutation points. The other fields always render their normal bytes.
fn http_request(host : String, port : Int) -> @boofuzz.CompiledRequest raise {
  let fixed = fn(bytes : Bytes) {
    @boofuzz.Field::simple(bytes, [], fuzzable=false)
  }
  @boofuzz.CompiledRequest::compile(
    @boofuzz.Block::new("http_request", [
      @boofuzz.Leaf("method", @boofuzz.Field::group([b"GET", b"POST", b"PUT"])),
      @boofuzz.Leaf("space1", fixed(b" ")),
      @boofuzz.Leaf(
        "path",
        @boofuzz.Field::simple(b"/echo", [b"/", b"/headers", b"/missing"]),
      ),
      @boofuzz.Leaf("space2", fixed(b" ")),
      @boofuzz.Leaf("version", fixed(b"HTTP/1.1")),
      @boofuzz.Leaf("request_line_end", fixed(b"\r\n")),
      @boofuzz.Nested(
        @boofuzz.Block::new("headers", [
          @boofuzz.Leaf(
            "host",
            fixed(@utf8.encode("Host: \{host}:\{port}\r\n")),
          ),
          @boofuzz.Leaf("fuzz_header", fixed(b"X-Fuzz: ")),
          @boofuzz.Leaf(
            "value",
            @boofuzz.Field::simple(b"seed", [b"", b"\x00\xff", b"AAAA"]),
          ),
          @boofuzz.Leaf("fuzz_header_end", fixed(b"\r\n")),
          @boofuzz.Leaf("connection", fixed(b"Connection: close\r\n")),
        ]),
      ),
      @boofuzz.Leaf("headers_end", fixed(b"\r\n")),
    ]),
  )
}

///|
/// Print the default request and each candidate without opening a socket.
/// Hex output preserves invalid UTF-8 and embedded zero bytes exactly.
fn show_offline(request : @boofuzz.CompiledRequest) -> Unit raise {
  println("default: \{@records.hex_encode(request.render())}")
  println(
    "mutation points: http_request.method, http_request.path, http_request.headers.value",
  )
  let cases = request.cases(limit=8)
  for ;; {
    match cases.next() {
      Some(case) =>
        println(
          "\{case.ordinal} \{case.field_path}:\{case.mutation_index} \{@records.hex_encode(case.payload)}",
        )
      None => break
    }
  }
}

///|
/// Run the same model against a TCP target. Each candidate gets a fresh
/// connection, and the response policy reads through the HTTP header end.
fn run_live(host : String, port : Int) -> Unit raise {
  let graph = @boofuzz.SessionGraph::new()
  graph.add(http_request(host, port))
  let paths = graph.paths(targets=["http_request"])
  let endpoint = @transport.Endpoint::new(
    host,
    port,
    connect_timeout_ms=750,
    receive_timeout_ms=750,
  )
  let policies : Map[String, @runner.ReadPolicy] = Map([
    ("http_request", @runner.Until(b"\r\n\r\n")),
  ])
  // Bound an unavailable target instead of retrying forever.
  let runner = @runner.Runner::new(
    paths,
    endpoint,
    policies~,
    limit=8,
    restart_threshold=Some(1),
    restart_sleep_ms=0,
  )
  for ;; {
    match runner.next() {
      Some(result) =>
        println(
          "\{result.case.field_path}:\{result.case.mutation_index} -> \{result.outcome.name()}",
        )
      None => break
    }
  }
  println("executed \{runner.executed()} cases")
}

///|
fn port_number(text : String) -> Int? {
  if text.is_empty() {
    return None
  }
  let mut value = 0
  for char in text {
    guard char >= '0' && char <= '9' else { return None }
    value = value * 10 + char.to_int() - '0'.to_int()
    guard value <= 65535 else { return None }
  }
  if value == 0 {
    None
  } else {
    Some(value)
  }
}

///|
fn usage() -> Unit {
  println(
    "usage:\n  moon run --target native examples/moonbit_http\n  moon run --target native examples/moonbit_http -- run [HOST] [PORT]",
  )
}

///|
fn execute(args : Array[String]) -> Unit raise {
  match args {
    [] => show_offline(http_request("127.0.0.1", 9000))
    ["run"] => run_live("127.0.0.1", 9000)
    ["run", host, port] =>
      match port_number(port) {
        Some(value) => run_live(host, value)
        None => {
          usage()
          exit_process(2)
        }
      }
    _ => {
      usage()
      exit_process(2)
    }
  }
}

///|
extern "c" fn exit_process(code : Int) -> Unit = "exit"

///|
fn main {
  execute(@env.args()[1:].to_owned()) catch {
    error => {
      println("moonbit_http: \{Repr(error)}")
      exit_process(2)
    }
  }
}
