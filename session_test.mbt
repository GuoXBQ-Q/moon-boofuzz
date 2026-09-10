///|
fn session_request(
  name : String,
  normal : Bytes,
) -> @moon_boofuzz.CompiledRequest raise {
  @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new(name, [
      Leaf("data", @moon_boofuzz.Field::simple(normal, [b"mutant"])),
    ]),
  )
}

///|
test "handshake authentication request path only mutates last request" {
  let graph = @moon_boofuzz.SessionGraph::new()
  graph.add(session_request("hello", b"HELLO"))
  graph.add(session_request("auth", b"AUTH"))
  graph.add(session_request("query", b"QUERY"))
  graph.connect("hello", "auth")
  graph.connect("auth", "query")
  let paths = graph.paths(targets=["query"])
  assert_eq(paths.length(), 1)
  assert_eq(paths[0].names(), ["hello", "auth", "query"])
  assert_eq(paths[0].prefix(), [b"HELLO", b"AUTH"])
  assert_eq(paths[0].cases().next().map(case => case.payload), Some(b"mutant"))
  let copy = paths[0].requests()
  copy.clear()
  assert_eq(paths[0].target().name(), "query")
  assert_eq(graph.paths().map(path => path.names()), [
    ["hello"],
    ["hello", "auth"],
    ["hello", "auth", "query"],
  ])
}

///|
test "DAG shared successor keeps distinct insertion ordered paths" {
  let graph = @moon_boofuzz.SessionGraph::new()
  for name in ["root", "a", "b", "end"] {
    graph.add(session_request(name, b""))
  }
  graph.connect("root", "b")
  graph.connect("root", "a")
  graph.connect("a", "end")
  graph.connect("b", "end")
  let paths = graph.paths(targets=["end"])
  assert_eq(paths.map(path => path.names()), [
    ["root", "b", "end"],
    ["root", "a", "end"],
  ])
  assert_true(
    try {
      graph.connect("end", "root")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      graph.connect("root", "unknown")
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(graph.paths(targets=["missing"]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(graph.paths(max_paths=1))
      false
    } catch {
      @moon_boofuzz.ModelError::Limit(_) => true
      _ => false
    },
  )
  assert_eq(
    graph.paths(targets=["end"]).map(path => path.names()),
    paths.map(path => path.names()),
  )
}
