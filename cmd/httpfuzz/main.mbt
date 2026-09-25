// SPDX-License-Identifier: GPL-2.0-only
// Tutorial companion for docs/CODE.md: a minimal HTTP GET fuzzer driven
// entirely from MoonBit code, no JSON definition involved.
//
//   moon run --target native cmd/httpfuzz                # offline: print the first payloads
//   moon run --target native cmd/httpfuzz -- run [HOST] [PORT]
//
// The live mode defaults to 127.0.0.1:9000; start any HTTP server there
// first. A target that never answers the dial is retried indefinitely
// (the upstream restart_threshold=None default), so stop with Ctrl+C.

///|
/// The protocol model: one named request, fields in wire order. Frozen
/// parts use candidates-empty simple fields; the fuzzable parts are a
/// method group and a string-library URI.
fn http_get() -> @boofuzz.CompiledRequest raise {
  @boofuzz.CompiledRequest::compile(
    @boofuzz.Block::new("get", [
      @boofuzz.Leaf("method", @boofuzz.Field::group([b"GET", b"POST", b"PUT"])),
      @boofuzz.Leaf("sp1", @boofuzz.Field::simple(b" ", [])),
      @boofuzz.Leaf("uri", @boofuzz.Field::text("/index.html")),
      @boofuzz.Leaf("sp2", @boofuzz.Field::simple(b" ", [])),
      @boofuzz.Leaf("version", @boofuzz.Field::text("HTTP/1.1", fuzzable=false)),
      @boofuzz.Leaf("crlf", @boofuzz.Field::simple(b"\r\n", [])),
      @boofuzz.Leaf(
        "head",
        @boofuzz.Field::simple(b"Host: 127.0.0.1:9000\r\n", []),
      ),
      @boofuzz.Leaf("end", @boofuzz.Field::delimiter("\r\n", fuzzable=false)),
    ]),
  )
}

///|
/// Offline enumeration: what `generate` prints for JSON definitions.
fn offline(request : @boofuzz.CompiledRequest) -> Unit raise {
  println("total mutations: \{request.raw_mutation_count()}")
  let stream = request.cases(limit=5)
  for ;; {
    match stream.next() {
      Some(case) =>
        println("\{case.id}: \{Repr(@utf8.decode_lossy(case.payload))}")
      None => break
    }
  }
}

///|
/// Live execution: every case gets a fresh connection, sends the frozen
/// prefix, then the mutated target; the read policy waits for the
/// response head before classifying the outcome.
fn live(
  paths : Array[@boofuzz.SessionPath],
  host : String,
  port : Int,
) -> Unit raise {
  let endpoint = @transport.Endpoint::new(host, port, receive_timeout_ms=500)
  let policies : Map[String, @runner.ReadPolicy] = Map([
    ("get", @runner.Until(b"\r\n\r\n")),
  ])
  let runner = @runner.Runner::new(paths, endpoint, policies~, limit=20)
  let mut executed = 0
  for ;; {
    match runner.next() {
      Some(result) => {
        executed += 1
        println("\{result.id} -> \{result.outcome.name()}")
      }
      None => break
    }
  }
  println("executed \{executed} cases")
}

///|
fn run(args : Array[String]) -> Unit raise {
  match args {
    [] => offline(http_get())
    ["run"] => live(build_paths(), "127.0.0.1", 9000)
    ["run", host] => live(build_paths(), host, 9000)
    ["run", host, port] =>
      match decimal(port) {
        Some(value) => live(build_paths(), host, value)
        None => {
          println("port must be a decimal number")
          exit_process(2)
        }
      }
    _ =>
      println(
        "usage:\n  moon run --target native cmd/httpfuzz                  # offline\n  moon run --target native cmd/httpfuzz -- run [HOST] [PORT]",
      )
  }
}

///|
fn build_paths() -> Array[@boofuzz.SessionPath] raise {
  let graph = @boofuzz.SessionGraph::new()
  graph.add(http_get())
  graph.paths(targets=["get"])
}

///|
fn decimal(text : String) -> Int? {
  if text.is_empty() {
    return None
  }
  let mut value = 0
  for ch in text {
    guard ch >= '0' && ch <= '9' else { return None }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    guard value <= 65535 else { return None }
  }
  Some(value)
}

///|
extern "c" fn exit_process(code : Int) -> Unit = "exit"

///|
fn main {
  let failed = try {
    run(@env.args()[1:].to_owned())
    false
  } catch {
    error => {
      println("moon-httpfuzz: \{Repr(error)}")
      true
    }
  }
  if failed {
    exit_process(2)
  }
}
