///|
pub(all) struct MutationCase {
  id : String
  request_name : String
  field_path : String
  mutation_index : Int
  ordinal : Int
  payload : Bytes
} derive(Debug, Eq)

///|
pub(all) enum EnumerationState {
  Running
  Exhausted
  Limited
  Stopped
} derive(Debug, Eq)

///|
pub struct CaseStream {
  request : CompiledRequest
  limit : Int
  mut entry : Int
  mut mutation : Int
  mut ordinal : Int
  mut emitted : Int
  mut state : EnumerationState
}

///|
pub fn CompiledRequest::cases(
  self : CompiledRequest,
  start? : Int = 0,
  limit? : Int = 10000,
) -> CaseStream raise ModelError {
  guard start >= 0 && limit >= 0 else {
    raise Invalid("negative enumeration start/limit")
  }
  let stream = {
    request: self,
    limit,
    entry: 0,
    mutation: 0,
    ordinal: start,
    emitted: 0,
    state: Running,
  }
  for remaining = start; stream.entry < self.entries.length(); {
    let count = self.entries[stream.entry].kind.count()
    if remaining < count {
      stream.mutation = remaining
      break
    }
    stream.entry += 1
    continue remaining - count
  }
  stream
}

///|
fn CaseStream::seek(self : CaseStream) -> Bool {
  while self.entry < self.request.entries.length() {
    let count = self.request.entries[self.entry].kind.count()
    if self.mutation < count {
      return true
    }
    self.entry += 1
    self.mutation = 0
  }
  false
}

///|
pub fn CaseStream::next(self : CaseStream) -> MutationCase? raise ModelError {
  guard self.state == Running else { return None }
  errdefer {
    self.state = Stopped
  }
  while self.seek() {
    guard self.emitted < self.limit else {
      self.state = Limited
      return None
    }
    guard self.ordinal < 2147483647 else {
      self.state = Stopped
      raise Limit("case ordinal overflow")
    }
    let entry = self.request.entries[self.entry]
    let mut depends_on_self = false
    for parent = Some(self.entry)
        parent is Some(i)
        parent = self.request.entries[i].parent {
      if self.request.entries[i].condition is Some(condition) &&
        condition.path() == entry.path {
        depends_on_self = true
      }
    }
    if !depends_on_self && !self.request.is_visible(self.entry, None) {
      self.mutation += 1
      self.ordinal += 1
      continue
    }
    if entry.kind is Atom(field) {
      guard (field.candidate_length)(self.mutation) <=
        self.request.max_bytes.to_int64() else {
        raise Limit(
          "field mutation exceeds request byte limit before allocation",
        )
      }
    }
    let value = entry.kind.candidate(self.mutation)
    if !self.request.is_visible(self.entry, Some((self.entry, value))) {
      self.mutation += 1
      self.ordinal += 1
      continue
    }
    let payload = self.request.render_node(0, Some((self.entry, value)))
    let case = {
      id: "v1:" + entry.path + ":\{self.mutation}",
      request_name: self.request.name,
      field_path: entry.path,
      mutation_index: self.mutation,
      ordinal: self.ordinal,
      payload,
    }
    self.mutation += 1
    self.ordinal += 1
    self.emitted += 1
    return Some(case)
  }
  self.state = Exhausted
  None
}

///|
pub fn CaseStream::stop(self : CaseStream) -> Unit {
  self.state = Stopped
}

///|
pub fn CaseStream::state(self : CaseStream) -> EnumerationState {
  self.state
}

///|
pub fn CaseStream::position(self : CaseStream) -> Int {
  self.ordinal
}

///|
/// Raw candidate positions, including candidates suppressed by hidden blocks.
pub fn CompiledRequest::raw_mutation_count(self : CompiledRequest) -> Int64 {
  self.entries.fold(init=0L, (total, entry) => {
    total + entry.kind.count().to_int64()
  })
}
