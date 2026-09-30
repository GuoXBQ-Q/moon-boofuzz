// SPDX-License-Identifier: GPL-2.0-only
// MoonBit twin of examples/http_post_full.json: a POST /echo with a JSON
// body. Mutation points: method (POST/PUT), Content-Length value (explicit
// candidates 0 / -1 / 999999999 — the classic length-mismatch probes),
// body (string library over the JSON text). Content-Length stays ASCII
// text: a simple field with string candidates, not an integer field,
// which would render binary.
// Offline: moon run --target native examples/http_post_full
// Live:    moon run --target native examples/http_post_full -- run 127.0.0.1 9000

///|
/// Frozen structural bytes: spaces, CRLF, header names — never mutated.
fn fixed(bytes : Bytes) -> @boofuzz.Field {
  @boofuzz.Field::simple(bytes, [], fuzzable=false)
}

///|
fn http_post(host : String, port : Int) -> @boofuzz.CompiledRequest raise {
  @boofuzz.CompiledRequest::compile(
    @boofuzz.Block::new("http_post", [
      @boofuzz.Leaf("verb", @boofuzz.Field::group([b"POST", b"PUT"])),
      @boofuzz.Leaf("sp1", fixed(b" ")),
      @boofuzz.Leaf("uri", fixed(b"/echo")),
      @boofuzz.Leaf("sp2", fixed(b" ")),
      @boofuzz.Leaf("version", fixed(b"HTTP/1.1")),
      @boofuzz.Leaf("crlf0", fixed(b"\r\n")),
      @boofuzz.Leaf(
        "name_host",
        fixed(@utf8.encode("Host: \{host}:\{port}\r\n")),
      ),
      @boofuzz.Leaf("name_ua", fixed(b"User-Agent: ")),
      @boofuzz.Leaf("ua", fixed(b"moon-boofuzz/0.1")),
      @boofuzz.Leaf("crlf2", fixed(b"\r\n")),
      @boofuzz.Leaf("name_ctype", fixed(b"Content-Type: ")),
      @boofuzz.Leaf("ctype", fixed(b"application/json")),
      @boofuzz.Leaf("crlf3", fixed(b"\r\n")),
      @boofuzz.Leaf("name_clen", fixed(b"Content-Length: ")),
      @boofuzz.Leaf(
        "clen",
        @boofuzz.Field::simple(b"21", [b"0", b"-1", b"999999999"]),
      ),
      @boofuzz.Leaf("crlf4", fixed(b"\r\n")),
      @boofuzz.Leaf("name_conn", fixed(b"Connection: ")),
      @boofuzz.Leaf("conn", fixed(b"close")),
      @boofuzz.Leaf("crlf5", fixed(b"\r\n")),
      @boofuzz.Leaf("head_end", fixed(b"\r\n")),
      @boofuzz.Leaf("body", @boofuzz.Field::text("{\"name\":\"fuzz\",\"n\":1}")),
    ]),
  )
}

///|
/// Print the default rendering and the first mutations.
fn show_offline(request : @boofuzz.CompiledRequest) -> Unit raise {
  println("== POST default ==")
  println(@utf8.decode_lossy(request.render()))
  let cases = request.cases(limit=8)
  for ;; {
    match cases.next() {
      Some(case) =>
        println(
          "\{case.field_path}:\{case.mutation_index} \{@records.hex_encode(case.payload)}",
        )
      None => break
    }
  }
}

///|
/// Execute the model against a TCP target, one fresh connection per
/// case, reading each response through the HTTP header end. A live web UI
/// is bound on the CLI's default port: the page shows live progress and
/// its pause button gates this loop between cases, like `boofuzz run`.
fn run_live(host : String, port : Int) -> Unit raise {
  let request = http_post(host, port)
  let graph = @boofuzz.SessionGraph::new()
  graph.add(request)
  let paths = graph.paths(targets=["http_post"])
  let endpoint = @transport.Endpoint::new(
    host,
    port,
    connect_timeout_ms=750,
    receive_timeout_ms=750,
  )
  let policies : Map[String, @runner.ReadPolicy] = Map([
    ("http_post", @runner.Until(b"\r\n\r\n")),
  ])
  // Live UI before the first case so the URL is known; the progress
  // denominator is the primitive-count total (upstream num_mutations).
  let webui = @web.WebUi::open(
    port=26000,
    total=request.raw_mutation_count().to_int(),
  )
  println("Web interface can be found at http://localhost:\{webui.port()}")
  // Bound an unavailable target instead of retrying forever; the case
  // limit itself stays unset (run to exhaustion).
  let runner = @runner.Runner::new(
    paths,
    endpoint,
    policies~,
    limit=@runner.NO_CASE_LIMIT,
    restart_threshold=Some(1),
    restart_sleep_ms=0,
  )
  for ;; {
    // Serve pending page requests; blocks here while the page is paused.
    webui.gate()
    match runner.next() {
      Some(result) => {
        webui.session().observe(runner.record(result))
        println(
          "\{result.case.field_path}:\{result.case.mutation_index} -> \{result.outcome.name()}",
        )
      }
      None => break
    }
  }
  // One last drain so the finished state is visible on the page.
  webui.serve()
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
fn main raise {
  let args = @env.args()[1:].to_owned()
  let host = if args.length() >= 2 { args[1] } else { "127.0.0.1" }
  let port = if args.length() >= 3 {
    match port_number(args[2]) {
      Some(port) => port
      None => {
        println("port must be 1-65535")
        return
      }
    }
  } else {
    9000
  }
  if args.length() >= 1 && args[0] == "run" {
    run_live(host, port)
  } else {
    show_offline(http_post("127.0.0.1", 9000))
  }
}
