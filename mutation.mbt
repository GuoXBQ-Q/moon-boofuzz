///|
pub(all) struct MutationCase {
  id : String
  request_name : String
  field_path : String
  mutation_index : Int
  ordinal : Int
  payload : Bytes
  /// Group candidates combined into this case, outer first; empty for
  /// single-field cases. The primary field_path/mutation_index stay last.
  extra : Array[(String, Int)]
} derive(Debug, Eq)

///|
pub(all) enum EnumerationState {
  Running
  Exhausted
  Limited
  Stopped
} derive(Debug, Eq)

///|
/// One stack frame of the lazy case-sequence walker. Sequence frames track
/// the next child, plain frames the next mutation index, product frames the
/// current group pass.
pub struct StreamFrame {
  seq : CaseSeq
  mut child : Int
  mut pass : Int
  mut walking : Bool
}

///|
/// A pre-enumerated unit of the base case sequence for combinatorial
/// enumeration. `is_group` marks parts contributed by a product's group,
/// which upstream adds without consulting the skip set. `child` is the
/// availability-checked leaf entry.
pub struct StreamUnit {
  parts : Array[(Int, Int, Bool)]
  child : Int
}

///|
pub struct CombFrame {
  mut unit_index : Int
  /// Fixed incoming skip: availability of every sibling unit is checked
  /// against this snapshot.
  incoming : Map[Int, Bool]
  /// Accumulating skip: upstream's new_skip is created once per level and
  /// updated in place across sibling iterations, so later siblings descend
  /// with a skip set that contains earlier ones (session.py:1165-1175).
  acc : Map[Int, Bool]
  parts : Array[(Int, Int, Bool)]
}

///|
pub struct CaseStream {
  request : CompiledRequest
  limit : Int
  mut skip : Int
  mut ordinal : Int
  mut emitted : Int
  mut state : EnumerationState
  stack : Array[StreamFrame]
  combinatorial : Bool
  units : Array[StreamUnit]
  max_depth : Int?
  mut depth : Int
  mut depth_emitted : Int
  frames : Array[CombFrame]
  vars : Map[String, Bytes]?
}

///|
pub fn CompiledRequest::cases(
  self : CompiledRequest,
  start? : Int = 0,
  limit? : Int = 10000,
  vars? : Map[String, Bytes]? = None,
) -> CaseStream raise ModelError {
  guard start >= 0 && limit >= 0 else {
    raise Invalid("negative enumeration start/limit")
  }
  {
    request: self,
    limit,
    skip: start,
    ordinal: start,
    emitted: 0,
    state: Running,
    stack: [{ seq: self.seq, child: 0, pass: 0, walking: false, }],
    combinatorial: false,
    units: [],
    max_depth: None,
    depth: 0,
    depth_emitted: 0,
    frames: [],
    vars,
  }
}

///|
fn CompiledRequest::collect_units(
  self : CompiledRequest,
  seq : CaseSeq,
  prefix : Array[(Int, Int, Bool)],
  out : Array[StreamUnit],
) -> Unit {
  match seq {
    Plain(entry) => {
      let count = self.entries[entry].kind.count()
      for i in 0..<count {
        let parts = prefix.copy()
        parts.push((entry, i, false))
        out.push({ parts, child: entry, })
      }
    }
    Sequence(children) =>
      for child in children {
        self.collect_units(child, prefix, out)
      }
    Product(group, inner) => {
      let passes = self.entries[group].kind.count()
      for gi in 0..<passes {
        let parts = prefix.copy()
        parts.push((group, gi, true))
        self.collect_units(inner, parts, out)
      }
    }
  }
}

///|
fn contains_duplicate_paths(
  request : CompiledRequest,
  parts : Array[(Int, Int, Bool)],
) -> Bool {
  let names = parts.map(part => request.entries[part.0].path)
  for i in 0..<names.length() {
    for j in (i + 1)..<names.length() {
      // Upstream drops combinations where any two qualified names are
      // substring-related (session.py _mutations_contain_duplicate, 518c139).
      if names[i].contains(names[j]) || names[j].contains(names[i]) {
        return true
      }
    }
  }
  false
}

///|
/// Enumerate combinatorial cases: depth 1..max_depth (indefinite when
/// max_depth is absent, stopping at the first depth without a valid case),
/// combining that many units of the base sequence, deduplicated exactly like
/// upstream. Group products take part as whole units.
pub fn CompiledRequest::cases_with_variables(
  self : CompiledRequest,
  vars : Map[String, Bytes]?,
  start? : Int = 0,
  limit? : Int = 10000,
) -> CaseStream raise ModelError {
  guard start >= 0 && limit >= 0 else {
    raise Invalid("negative enumeration start/limit")
  }
  {
    request: self,
    limit,
    skip: start,
    ordinal: start,
    emitted: 0,
    state: Running,
    stack: [{ seq: self.seq, child: 0, pass: 0, walking: false, }],
    combinatorial: false,
    units: [],
    max_depth: None,
    depth: 0,
    depth_emitted: 0,
    frames: [],
    vars,
  }
}

///|
pub fn CompiledRequest::combinatorial_cases_with_variables(
  self : CompiledRequest,
  vars : Map[String, Bytes]?,
  start? : Int = 0,
  limit? : Int = 10000,
  max_depth? : Int,
) -> CaseStream raise ModelError {
  guard start >= 0 && limit >= 0 else {
    raise Invalid("negative enumeration start/limit")
  }
  let units : Array[StreamUnit] = []
  self.collect_units(self.seq, [], units)
  {
    request: self,
    limit,
    skip: start,
    ordinal: start,
    emitted: 0,
    state: Running,
    stack: [],
    combinatorial: true,
    units,
    max_depth,
    depth: 1,
    depth_emitted: 0,
    frames: [{ unit_index: 0, incoming: Map([]), acc: Map([]), parts: [], }],
    vars,
  }
}

///|
/// Enumerate combinatorial cases: depth 1..max_depth (indefinite when
/// max_depth is absent, stopping at the first depth without a valid case),
/// combining that many units of the base sequence, deduplicated exactly like
/// upstream. Group products take part as whole units.
pub fn CompiledRequest::combinatorial_cases(
  self : CompiledRequest,
  start? : Int = 0,
  limit? : Int = 10000,
  max_depth? : Int,
) -> CaseStream raise ModelError {
  guard start >= 0 && limit >= 0 else {
    raise Invalid("negative enumeration start/limit")
  }
  let units : Array[StreamUnit] = []
  self.collect_units(self.seq, [], units)
  {
    request: self,
    limit,
    skip: start,
    ordinal: start,
    emitted: 0,
    state: Running,
    stack: [],
    combinatorial: true,
    units,
    max_depth,
    depth: 1,
    depth_emitted: 0,
    frames: [{ unit_index: 0, incoming: Map([]), acc: Map([]), parts: [], }],
    vars: None,
  }
}

///|
/// Advance the sequential tree walker to the next case position, returning
/// the mutated (entry, mutation index) pairs, outermost group first.
fn CaseStream::find(self : CaseStream) -> Array[(Int, Int)]? {
  while self.stack.length() > 0 {
    let frame = self.stack[self.stack.length() - 1]
    match frame.seq {
      Plain(entry) => {
        let count = self.request.entries[entry].kind.count()
        if frame.child < count {
          let mutation = frame.child
          frame.child += 1
          let parts : Array[(Int, Int)] = []
          for f in self.stack {
            if f.seq is Product(group, _) && f.walking {
              parts.push((group, f.pass))
            }
          }
          parts.push((entry, mutation))
          return Some(parts)
        }
        ignore(self.stack.pop())
      }
      Sequence(children) =>
        if frame.child < children.length() {
          let next = children[frame.child]
          frame.child += 1
          self.stack.push({ seq: next, child: 0, pass: 0, walking: false, })
        } else {
          ignore(self.stack.pop())
        }
      Product(_, inner) => {
        let group = match frame.seq {
          Product(group, _) => group
          _ => 0
        }
        let passes = self.request.entries[group].kind.count()
        if frame.walking {
          frame.walking = false
          frame.pass += 1
        } else if frame.pass < passes {
          frame.walking = true
          self.stack.push({ seq: inner, child: 0, pass: 0, walking: false, })
        } else {
          ignore(self.stack.pop())
        }
      }
    }
  }
  None
}

///|
/// Advance the combinatorial walker, returning the combined (entry, mutation
/// index) pairs of the next valid case, or None when enumeration ends.
fn CaseStream::comb_step(self : CaseStream) -> Array[(Int, Int)]? {
  while self.frames.length() > 0 {
    let frame = self.frames[self.frames.length() - 1]
    let mut descended = false
    while frame.unit_index < self.units.length() {
      let unit = self.units[frame.unit_index]
      frame.unit_index += 1
      if frame.incoming.contains(unit.child) {
        continue
      }
      if self.frames.length() < self.depth {
        let child_skip : Map[Int, Bool] = Map([])
        for key, _ in frame.acc {
          child_skip[key] = true
        }
        let parts = frame.parts.copy()
        for part in unit.parts {
          child_skip[part.0] = true
          parts.push(part)
        }
        // The accumulating set keeps growing for later siblings.
        for part in unit.parts {
          frame.acc[part.0] = true
        }
        self.frames.push({
          unit_index: 0,
          incoming: child_skip,
          acc: child_skip.copy(),
          parts,
        })
        descended = true
        break
      }
      let all = frame.parts.copy()
      for part in unit.parts {
        all.push(part)
      }
      if !contains_duplicate_paths(self.request, all) {
        self.depth_emitted += 1
        return Some(all.map(part => (part.0, part.1)))
      }
    }
    if descended {
      continue
    }
    ignore(self.frames.pop())
    if self.frames.is_empty() {
      // The depth finished; stop when it produced nothing or the maximum
      // depth is reached (session.py _generate_mutations_indefinitely).
      if self.depth_emitted == 0 {
        return None
      }
      match self.max_depth {
        Some(maximum) => if self.depth >= maximum { return None }
        None => ()
      }
      self.depth += 1
      self.depth_emitted = 0
      self.frames.push({
        unit_index: 0,
        incoming: Map([]),
        acc: Map([]),
        parts: [],
      })
    }
  }
  None
}

///|
fn CaseStream::build_case(
  self : CaseStream,
  parts : Array[(Int, Int)],
) -> MutationCase raise ModelError {
  let leaf = parts[parts.length() - 1]
  let kind = self.request.entries[leaf.0].kind
  if kind is Atom(field) {
    guard (field.candidate_length)(leaf.1) <= self.request.max_bytes.to_int64() else {
      raise Limit("field mutation exceeds request byte limit before allocation")
    }
  }
  let replacements : Array[(Int, Bytes)] = []
  let extra : Array[(String, Int)] = []
  for part in parts {
    let candidate = self.request.entries[part.0].kind.candidate(part.1)
    replacements.push((part.0, candidate))
    if part.0 != leaf.0 || part.1 != leaf.1 {
      extra.push((self.request.entries[part.0].path, part.1))
    }
  }
  // Upstream always emits a test case per candidate; blocks whose
  // dependencies disallow rendering contribute empty bytes
  // (boofuzz/blocks/block.py encode, 518c139).
  let payload = self.request.render_node(0, replacements, self.vars)
  let identity = parts
    .map(part => self.request.entries[part.0].path + ":\{part.1}")
    .join("+")
  {
    id: "v1:" + identity,
    request_name: self.request.name,
    field_path: self.request.entries[leaf.0].path,
    mutation_index: leaf.1,
    ordinal: self.ordinal,
    payload,
    extra,
  }
}

///|
pub fn CaseStream::next(self : CaseStream) -> MutationCase? raise ModelError {
  guard self.state == Running else { return None }
  errdefer {
    self.state = Stopped
  }
  while self.skip > 0 {
    let found = if self.combinatorial { self.comb_step() } else { self.find() }
    guard found is Some(_) else {
      self.state = Exhausted
      return None
    }
    self.skip -= 1
  }
  guard self.emitted < self.limit else {
    self.state = Limited
    return None
  }
  guard self.ordinal < 2147483647 else {
    self.state = Stopped
    raise Limit("case ordinal overflow")
  }
  let found = if self.combinatorial { self.comb_step() } else { self.find() }
  let parts = match found {
    Some(parts) => parts
    None => {
      self.state = Exhausted
      return None
    }
  }
  let case = self.build_case(parts)
  self.ordinal += 1
  self.emitted += 1
  Some(case)
}

///|
/// All mutated (path, mutation index) pairs of this case, outermost first.
pub fn MutationCase::parts(self : MutationCase) -> Array[(String, Int)] {
  let all = self.extra.copy()
  all.push((self.field_path, self.mutation_index))
  all
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
/// Cases not yet consumed from the start offset; nonzero after a stream
/// exhausts before reaching it.
pub fn CaseStream::remaining_skip(self : CaseStream) -> Int {
  self.skip
}

///|
fn CompiledRequest::seq_count(self : CompiledRequest, seq : CaseSeq) -> Int64 {
  match seq {
    Plain(entry) => self.entries[entry].kind.count().to_int64()
    Sequence(children) => {
      let mut total = 0L
      for child in children {
        total += self.seq_count(child)
      }
      total
    }
    Product(group, inner) =>
      self.entries[group].kind.count().to_int64() * self.seq_count(inner)
  }
}

///|
/// Case positions of the sequential stream, including positions inside group
/// product replays.
pub fn CompiledRequest::raw_mutation_count(self : CompiledRequest) -> Int64 {
  self.seq_count(self.seq)
}

///|
/// Number of sequential cases contributed by the entry at `path` (the
/// entry's own candidate count; group product replays are excluded).
pub fn CompiledRequest::count_at(
  self : CompiledRequest,
  path : String,
) -> Int raise ModelError {
  self.entries[self.resolve(path)].kind.count()
}
