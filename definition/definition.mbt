///|
pub struct ProtocolDefinition {
  requests : Array[@core.CompiledRequest]
  paths : Array[@core.SessionPath]
  execution_text : String?
}

///|
pub fn ProtocolDefinition::parse(source : String) -> ProtocolDefinition raise {
  let value = @json.parse(source)
  @records.require_keys(value, [
    "schema_version", "requests", "edges", "targets", "max_bytes", "max_paths", "execution",
  ])
  let version : Int = @json.from_json(required(value, "schema_version"))
  guard version == 1 else { raise UnsupportedVersion(version) }
  let descriptions : Array[Json] = @json.from_json(required(value, "requests"))
  let requests = descriptions.map(description => {
    @core.CompiledRequest::compile(
      parse_block(description, 0, true),
      max_bytes=number(value, "max_bytes", 1048576),
    )
  })
  let graph = @core.SessionGraph::new()
  for request in requests {
    graph.add(request)
  }
  if property(value, "edges") is Some(edges) {
    guard edges is Array(edges) else { raise Invalid("edges must be an array") }
    for edge in edges {
      guard edge is [String(from), String(to)] else {
        raise Invalid("edge must have two request names")
      }
      graph.connect(from, to)
    }
  }
  let max_paths = number(value, "max_paths", 10000)
  let paths = match property(value, "targets") {
    None => graph.paths(max_paths~)
    Some(targets) => graph.paths(targets=@json.from_json(targets), max_paths~)
  }
  {
    requests,
    paths,
    execution_text: property(value, "execution").map(json => json.stringify()),
  }
}

///|
pub fn ProtocolDefinition::requests(
  self : ProtocolDefinition,
) -> Array[@core.CompiledRequest] {
  self.requests.copy()
}

///|
pub fn ProtocolDefinition::paths(
  self : ProtocolDefinition,
) -> Array[@core.SessionPath] {
  self.paths.copy()
}

///|
pub fn ProtocolDefinition::execution(self : ProtocolDefinition) -> Json? {
  self.execution_text.map(text => try! @json.parse(text))
}

///|
pub(all) struct GeneratedCase {
  case_id : String
  path : Array[String]
  prefix : Array[Bytes]
  case : @core.MutationCase
} derive(Debug)

///|
pub(all) struct GenerationResult {
  generated : Int
  state : @core.EnumerationState
} derive(Debug, Eq)

///|
/// Resolve a stable case identity ("v1:request.field:index") to the raw
/// sequential start position that reproduces exactly that case.
pub fn ProtocolDefinition::position_of_id(
  self : ProtocolDefinition,
  id : String,
) -> Int raise {
  guard id.has_prefix("v1:") else {
    raise Invalid("case id must start with v1:")
  }
  let body = id[3:]
  guard body.contains(":") else { raise Invalid("case id missing field index") }
  let mut cut = body.length() - 1
  while cut > 0 && body[cut] != ':' {
    cut -= 1
  }
  let field_path = body[:cut].to_owned()
  let index_text = body[cut + 1:].to_owned()
  let index = parse_case_index(index_text)
  let mut offset = 0
  let mut found = false
  for request in self.requests {
    let mut entry_index = -1
    for i, path in request.paths() {
      if path == field_path {
        entry_index = i
      }
    }
    if entry_index >= 0 {
      // Sum counts of every entry before the requested field.
      let paths = request.paths()
      for i in 0..<entry_index {
        offset += request.count_at(paths[i])
      }
      offset += index
      found = true
      break
    }
    offset += request.raw_mutation_count().to_int()
  }
  guard found else { raise Invalid("unknown case field path: " + field_path) }
  offset
}

///|
fn parse_case_index(text : String) -> Int raise DefinitionError {
  let value = decimal_u64(text)
  guard value <= 2147483647UL else { raise Invalid("case index too large") }
  value.to_int()
}

///|
pub fn ProtocolDefinition::generate(
  self : ProtocolDefinition,
  emit : (GeneratedCase) -> Bool raise,
  start? : Int = 0,
  limit? : Int = 10000,
  combinatorial? : Bool = false,
  max_depth? : Int,
) -> GenerationResult raise {
  guard start >= 0 && limit >= 0 else {
    raise Invalid("negative generation start or limit")
  }
  let mut skip = start
  let mut generated = 0
  for path in self.paths {
    if combinatorial {
      // Combinatorial totals are unknown up front; the start position walks
      // emitted cases and any remainder carries into the next path.
      let stream = path.combinatorial_cases_with_variables(
        None,
        start=skip,
        limit=2147483647,
        max_depth?,
      )
      skip = 0
      let mut exhausted = false
      for ;; {
        if generated >= limit {
          return { generated, state: Limited, }
        }
        match stream.next() {
          Some(case) => {
            let names = path.names()
            let keep_going = emit({
              case_id: names.to_json().stringify() + "/" + case.id,
              path: names,
              prefix: path.prefix(),
              case,
            })
            generated += 1
            if !keep_going {
              return { generated, state: Stopped, }
            }
          }
          None => {
            exhausted = true
            break
          }
        }
      }
      if exhausted {
        skip = stream.remaining_skip()
      }
      continue
    }
    let count = path.target().raw_mutation_count()
    if skip.to_int64() >= count {
      skip -= count.to_int()
      continue
    }
    let stream = path.cases(start=skip, limit=2147483647)
    skip = 0
    for ;; {
      if generated >= limit {
        return { generated, state: Limited, }
      }
      guard stream.next() is Some(case) else { break }
      let names = path.names()
      let keep_going = emit({
        case_id: names.to_json().stringify() + "/" + case.id,
        path: names,
        prefix: path.prefix(),
        case,
      })
      generated += 1
      if !keep_going {
        return { generated, state: Stopped, }
      }
    }
  }
  { generated, state: Exhausted, }
}
