///|
/// Context handed to an edge callback: the mutable session-variable map for
/// the running case, bytes received from earlier steps, and the destination
/// request name. Mirrors upstream's ProtocolSession (protocol_session.py,
/// 518c139); callbacks write variables and may return replacement data.
pub(all) struct StepContext {
  variables : Map[String, Bytes]
  received : Array[Bytes]
  request : String
}

///|
pub struct SessionGraph {
  requests : Array[CompiledRequest]
  edges : Array[Array[Int]]
  names : Map[String, Int]
  edge_callbacks : Map[(Int, Int), (StepContext) -> Bytes?]
}

///|
pub fn SessionGraph::new() -> SessionGraph {
  { requests: [], edges: [], names: Map([]), edge_callbacks: Map([]), }
}

///|
pub fn SessionGraph::add(
  self : SessionGraph,
  request : CompiledRequest,
) -> Unit raise ModelError {
  guard !self.names.contains(request.name) else {
    raise Invalid("duplicate session request: " + request.name)
  }
  self.names[request.name] = self.requests.length()
  self.requests.push(request)
  self.edges.push([])
}

///|
fn SessionGraph::resolve(
  self : SessionGraph,
  name : String,
) -> Int raise ModelError {
  self.names
  .get(name)
  .unwrap_or_else(() => raise Invalid("unknown session request: " + name))
}

///|
pub fn SessionGraph::connect(
  self : SessionGraph,
  from : String,
  to : String,
  callback? : (StepContext) -> Bytes?,
) -> Unit raise ModelError {
  let source = self.resolve(from)
  let target = self.resolve(to)
  guard !self.edges[source].contains(target) else {
    raise Invalid("duplicate session edge")
  }
  let pending = [target]
  let seen = Array::make(self.requests.length(), false)
  while pending.pop() is Some(index) {
    guard index != source else { raise Invalid("session graph cycle") }
    if seen[index] {
      continue
    }
    seen[index] = true
    for next in self.edges[index] {
      pending.push(next)
    }
  }
  self.edges[source].push(target)
  match callback {
    Some(function) => self.edge_callbacks[(source, target)] = function
    None => ()
  }
}

///|
pub struct SessionPath {
  requests : Array[CompiledRequest]
  /// Callback on the edge into each request; roots have None. Sourced from
  /// SessionGraph::connect (upstream edge callbacks, session.py:754-794).
  transitions : Array[((StepContext) -> Bytes?)?]
}

///|
pub fn SessionPath::requests(self : SessionPath) -> Array[CompiledRequest] {
  self.requests.copy()
}

///|
pub fn SessionPath::names(self : SessionPath) -> Array[String] {
  self.requests.map(request => request.name)
}

///|
pub fn SessionPath::target(self : SessionPath) -> CompiledRequest {
  self.requests[self.requests.length() - 1]
}

///|
/// Only the terminal request mutates; prefixes are rendered from their defaults.
pub fn SessionPath::cases(
  self : SessionPath,
  start? : Int = 0,
  limit? : Int = 10000,
  variables? : Map[String, Bytes]? = None,
) -> CaseStream raise ModelError {
  self.target().cases(start~, limit~, vars=variables)
}

///|
pub fn SessionPath::cases_with_variables(
  self : SessionPath,
  vars : Map[String, Bytes]?,
  start? : Int = 0,
  limit? : Int = 10000,
) -> CaseStream raise ModelError {
  self.target().cases_with_variables(vars, start~, limit~)
}

///|
pub fn SessionPath::combinatorial_cases_with_variables(
  self : SessionPath,
  vars : Map[String, Bytes]?,
  start? : Int = 0,
  limit? : Int = 10000,
  max_depth? : Int,
) -> CaseStream raise ModelError {
  match max_depth {
    Some(depth) =>
      self
      .target()
      .combinatorial_cases_with_variables(vars, start~, limit~, max_depth=depth)
    None =>
      self.target().combinatorial_cases_with_variables(vars, start~, limit~)
  }
}

///|
pub fn SessionPath::prefix(self : SessionPath) -> Array[Bytes] raise ModelError {
  self.requests[:self.requests.length() - 1]
  .to_owned()
  .map(request => request.render())
}

///|
fn SessionGraph::walk(
  self : SessionGraph,
  index : Int,
  prefix : Array[CompiledRequest],
  transitions : Array[((StepContext) -> Bytes?)?],
  targets : Array[Int]?,
  reachable : Array[Bool],
  max_paths : Int,
  output : Array[SessionPath],
) -> Unit raise ModelError {
  guard prefix.length() < 256 else {
    raise Limit("session path exceeds 256 requests")
  }
  let path = prefix.copy()
  path.push(self.requests[index])
  // Transitions stay aligned with the path: one entry per request, the
  // callback on the edge into it (None for roots).
  let path_transitions = transitions.copy()
  if path_transitions.is_empty() {
    path_transitions.push(None)
  }
  if targets.map(values => values.contains(index)).unwrap_or(true) {
    guard output.length() < max_paths else {
      raise Limit("session path count limit")
    }
    output.push({ requests: path, transitions: path_transitions, })
  }
  for child in self.edges[index] {
    if reachable[child] {
      let child_transitions = path_transitions.copy()
      child_transitions.push(self.edge_callbacks.get((index, child)))
      self.walk(
        child, path, child_transitions, targets, reachable, max_paths, output,
      )
    }
  }
}

///|
/// Roots follow node insertion order; outgoing edges follow connection order.
pub fn SessionGraph::paths(
  self : SessionGraph,
  targets? : Array[String],
  max_paths? : Int = 10000,
) -> Array[SessionPath] raise ModelError {
  guard max_paths >= 0 else { raise Invalid("negative path limit") }
  let selected = targets.map(names => names.map(name => self.resolve(name)))
  let reachable = Array::make(self.requests.length(), selected is None)
  if selected is Some(indices) {
    let pending = indices.copy()
    while pending.pop() is Some(index) {
      if reachable[index] {
        continue
      }
      reachable[index] = true
      for source, edges in self.edges {
        if edges.contains(index) {
          pending.push(source)
        }
      }
    }
  }
  let incoming = Array::make(self.requests.length(), false)
  for edges in self.edges {
    for target in edges {
      incoming[target] = true
    }
  }
  let output : Array[SessionPath] = []
  for index in 0..<self.requests.length() {
    if !incoming[index] && reachable[index] {
      self.walk(index, [], [], selected, reachable, max_paths, output)
    }
  }
  output
}
