///|
/// Named protocol items. Names are one path segment and cannot contain dots.
pub(all) enum Node {
  Leaf(String, Field)
  Nested(Block)
  Repeat(String, String, Int, Int, Int, String?)
  Sized(String, SizeSpec)
  Checksummed(String, ChecksumSpec)
  Mirrored(String, String)
  Dynamic(String, String, Field)
}

///|
pub struct Block {
  name : String
  children : Array[Node]
  condition : Condition?
  alignment : (Int, Bytes)?
  group : String?
}

///|
pub fn Block::new(name : String, children : Array[Node]) -> Block {
  {
    name,
    children: children.copy(),
    condition: None,
    alignment: None,
    group: None,
  }
}

///|
/// Link the block to a Group field; its candidates multiply with the block's
/// own mutation cases like upstream Block(group=...) (boofuzz/blocks/block.py
/// mutations, 518c139). The target is a full field path.
pub fn Block::with_group(self : Block, target : String) -> Block {
  { ..self, group: Some(target), }
}

///|
priv enum EntryKind {
  Atom(Field)
  Dynamic(Field, String)
  Container(Array[Int])
  Repetition(String, Int, Int, Int, String?)
  ComputedSize(SizeSpec)
  ComputedChecksum(ChecksumSpec)
  Mirror(String)
}

///|
struct Entry {
  path : String
  parent : Int?
  kind : EntryKind
  condition : Condition?
  alignment : (Int, Bytes)?
  group : String?
}

///|
/// Lazy case sequence tree. Upstream enumerates a block as its plain child
/// mutations followed by group products replaying that same sequence once
/// per group candidate (boofuzz/blocks/block.py mutations, 518c139).
pub enum CaseSeq {
  Plain(Int)
  Sequence(Array[CaseSeq])
  Product(Int, CaseSeq)
}

///|
pub struct CompiledRequest {
  name : String
  entries : Array[Entry]
  paths : Map[String, Int]
  max_bytes : Int
  seq : CaseSeq
}

///|
/// Build the lazy case sequence for an entry. A grouped block replays its
/// children sequence once per group candidate after the plain pass.
fn build_case_seq(
  entries : Array[Entry],
  paths : Map[String, Int],
  groups : Map[Int, Int],
  index : Int,
) -> CaseSeq raise ModelError {
  match entries[index].kind {
    Container(children) => {
      let inner = Sequence(
        children.map(child => build_case_seq(entries, paths, groups, child)),
      )
      match groups.get(index) {
        Some(group_entry) => Sequence([inner, Product(group_entry, inner)])
        None => inner
      }
    }
    Mirror(_) => Sequence([])
    kind => if kind.count() > 0 { Plain(index) } else { Sequence([]) }
  }
}

///|
fn valid_name(name : String) -> Bool {
  !name.is_empty() &&
  !name.contains(".") &&
  !name.contains("/") &&
  !name.contains("+")
}

///|
fn add_node(
  node : Node,
  prefix : String,
  parent : Int?,
  entries : Array[Entry],
  paths : Map[String, Int],
  depth : Int,
) -> Int raise ModelError {
  guard depth <= 256 else { raise Invalid("nesting depth exceeds 256") }
  let name = match node {
    Leaf(name, _)
    | Repeat(name, _, _, _, _, _)
    | Sized(name, _)
    | Checksummed(name, _)
    | Mirrored(name, _)
    | Dynamic(name, _, _) => name
    Nested(block) => block.name
  }
  guard valid_name(name) else { raise Invalid("invalid name: " + name) }
  let path = if prefix.is_empty() { name } else { prefix + "." + name }
  guard !paths.contains(path) else { raise Invalid("duplicate path: " + path) }
  let index = entries.length()
  paths[path] = index
  let kind = match node {
    Leaf(_, field) => Atom(field)
    Dynamic(_, variable, field) => Dynamic(field, variable)
    Nested(_) => Container([])
    Sized(_, spec) => ComputedSize(spec)
    Checksummed(_, spec) => ComputedChecksum(spec)
    Mirrored(_, target) => Mirror(target)
    Repeat(_, target, min, max, step, variable) => {
      guard min >= 0 && max >= min && step > 0 else {
        raise Invalid("invalid repeat range or step")
      }
      guard (max - min) / step < 2147483647 else {
        raise Invalid("repeat count overflow")
      }
      Repetition(target, min, max, step, variable)
    }
  }
  let condition = match node {
    Nested(block) => block.condition
    _ => None
  }
  let alignment = match node {
    Nested(block) => block.alignment
    _ => None
  }
  let group = match node {
    Nested(block) => block.group
    _ => None
  }
  entries.push({ path, parent, kind, condition, alignment, group, })
  if node is Nested(block) {
    let children = block.children.map(child => {
      add_node(child, path, Some(index), entries, paths, depth + 1)
    })
    entries[index] = {
      path,
      parent,
      kind: Container(children),
      condition,
      alignment,
      group,
    }
  }
  index
}

///|
/// Validate and snapshot a named protocol tree. Limits count encoded wire bytes.
pub fn CompiledRequest::compile(
  root : Block,
  max_bytes? : Int = 1048576,
) -> CompiledRequest raise ModelError {
  guard max_bytes >= 0 else { raise Invalid("negative request byte limit") }
  let entries : Array[Entry] = []
  let paths : Map[String, Int] = Map([])
  ignore(add_node(Nested(root), "", None, entries, paths, 0))
  // Resolve group references; a Group candidate multiplies the cases of the
  // block that references it (upstream resolves by name at mutation time).
  let groups : Map[Int, Int] = Map([])
  for i, entry in entries {
    if entry.group is Some(target) {
      let group_entry = paths
        .get(target)
        .unwrap_or_else(() => raise Invalid("unknown path: " + target))
      guard entries[group_entry].kind is Atom(_) else {
        raise Invalid("group target must be a field")
      }
      groups[i] = group_entry
    }
  }
  let seq = build_case_seq(entries, paths, groups, 0)
  let request = { name: root.name, entries, paths, max_bytes, seq, }
  for entry in entries {
    if entry.kind is Repetition(path, _, _, _, _) {
      let target = request.resolve(path)
      let current = request.resolve(entry.path)
      guard entries[target].kind is Container(_) &&
        target < current &&
        !entry.path.has_prefix(path + ".") else {
        raise Invalid("repeat target must be a completed preceding block")
      }
    }
    if entry.condition is Some(condition) {
      let target = request.resolve(condition.path())
      guard entries[target].kind is Atom(_) ||
        entries[target].kind is Dynamic(_, _) else {
        raise Invalid("condition target must be a field")
      }
    }
    if entry.kind is Mirror(target) {
      // A mirror may not live inside its target's subtree; indirect cycles
      // are broken by the active chain during rendering.
      let target_index = request.resolve(target)
      let mut parent = entry.parent
      while parent is Some(p) {
        guard p != target_index else {
          raise Invalid("mirror target contains the mirror")
        }
        parent = entries[p].parent
      }
    }
  }
  request.validate_sizes()
  request.validate_checksums()
  ignore(request.render())
  request
}

///|
pub fn CompiledRequest::name(self : CompiledRequest) -> String {
  self.name
}

///|
pub fn CompiledRequest::paths(self : CompiledRequest) -> Array[String] {
  self.entries.map(entry => entry.path)
}

///|
pub fn CompiledRequest::parent_path(
  self : CompiledRequest,
  path : String,
) -> String? raise ModelError {
  self.entries[self.resolve(path)].parent.map(index => self.entries[index].path)
}

///|
fn CompiledRequest::resolve(
  self : CompiledRequest,
  path : String,
) -> Int raise ModelError {
  self.paths
  .get(path)
  .unwrap_or_else(() => raise Invalid("unknown path: " + path))
}

///|
/// Multi-point render replacements: (entry index, candidate bytes) pairs.
/// Entry indices are unique by construction, so at most one pair matches
/// any node; the first match wins.
type Replacements = Array[(Int, Bytes)]

///|
fn zero_byte() -> Byte {
  let zero : Int = 0
  zero.to_byte()
}

///|
fn Replacements::lookup(self : Replacements, index : Int) -> Bytes? {
  for pair in self {
    let (target, value) = pair
    if target == index {
      return Some(value)
    }
  }
  None
}

///|
fn CompiledRequest::render_node(
  self : CompiledRequest,
  index : Int,
  replacements : Replacements,
  vars : Map[String, Bytes]?,
  active? : Array[Int] = [],
) -> Bytes raise ModelError {
  guard self.is_visible(index, replacements, vars) else { return Bytes::new(0) }
  if !(self.entries[index].kind is Repetition(_, _, _, _, _)) {
    match replacements.lookup(index) {
      Some(value) => {
        guard value.length() <= self.max_bytes else {
          raise Limit("request byte limit: " + self.entries[index].path)
        }
        return value
      }
      None => ()
    }
  }
  match self.entries[index].kind {
    ComputedChecksum(spec) => {
      if active.contains(index) {
        return Bytes::makei(4, fn(_) { zero_byte() })
      }
      let nested = active.copy()
      nested.push(index)
      let bytes = self.render_node(
        self.resolve(spec.target),
        replacements,
        vars,
        active=nested,
      )
      encode_integer(crc32(bytes).to_uint64(), 32, spec.endian)
    }
    ComputedSize(spec) => self.size_value(spec, replacements, vars)
    Mirror(target) => {
      if active.contains(index) {
        return Bytes::new(0)
      }
      let nested = active.copy()
      nested.push(index)
      self.render_node(self.resolve(target), replacements, vars, active=nested)
    }
    Repetition(path, _, _, _, variable) => {
      let count = match replacements.lookup(index) {
        Some(value) => decode_repeat(value)
        None =>
          // Dynamic repetition resolves its count from session variables;
          // outside a test case it falls back to zero like upstream's
          // ProtocolSessionReference(name, default_value=0).
          match variable {
            Some(name) =>
              match vars {
                Some(map) =>
                  match map.get(name) {
                    Some(bytes) => {
                      guard bytes.length() >= 4 else {
                        raise Invalid("repeat variable needs 4 bytes")
                      }
                      decode_repeat(bytes)
                    }
                    None => raise Invalid("missing session variable: " + name)
                  }
                None => 0
              }
            None => 0
          }
      }
      let bytes = self.render_node(
        self.resolve(path),
        replacements,
        vars,
        active~,
      )
      guard bytes.is_empty() || count <= self.max_bytes / bytes.length() else {
        raise Limit("repeated block exceeds byte limit")
      }
      bytes.repeat(count)
    }
    Dynamic(field, variable) =>
      // Upstream resolves ProtocolSessionReference values from the protocol
      // session inside a test case and falls back to the stored default
      // outside it (fuzzable.py original_value, 518c139).
      match vars {
        Some(map) =>
          match map.get(variable) {
            Some(bytes) => bytes
            None => raise Invalid("missing session variable: " + variable)
          }
        None => field.value
      }
    Atom(field) => {
      guard field.value.length() <= self.max_bytes else {
        raise Limit("request byte limit: " + self.entries[index].path)
      }
      field.value
    }
    Container(children) => {
      let output : Array[Byte] = []
      for child in children {
        let bytes = self.render_node(child, replacements, vars, active~)
        guard bytes.length() <= self.max_bytes - output.length() else {
          raise Limit("request byte limit: " + self.entries[index].path)
        }
        for byte in bytes {
          output.push(byte)
        }
      }
      if self.entries[index].alignment is Some((modulus, pattern)) {
        let padding = modulus - output.length() % modulus
        guard padding <= self.max_bytes - output.length() else {
          raise Limit("aligned block exceeds byte limit")
        }
        for i in 0..<padding {
          output.push(pattern[i % pattern.length()])
        }
      }
      Bytes::from_array(output)
    }
  }
}

///|
pub fn CompiledRequest::render(
  self : CompiledRequest,
) -> Bytes raise ModelError {
  self.render_node(0, [], None)
}

///|
/// Render with session variables; inside a running case dynamic fields
/// resolve strictly, matching upstream node.render(mutation_context).
pub fn CompiledRequest::render_with(
  self : CompiledRequest,
  vars : Map[String, Bytes]?,
) -> Bytes raise ModelError {
  self.render_node(0, [], vars)
}

///|
/// Render a mutation case (parts from MutationCase::parts) with session
/// variables, so edge-callback variable writes are visible at send time.
pub fn CompiledRequest::render_case(
  self : CompiledRequest,
  parts : Array[(String, Int)],
  vars : Map[String, Bytes]?,
) -> Bytes raise ModelError {
  let replacements : Replacements = []
  for part in parts {
    let index = self.resolve(part.0)
    replacements.push((index, self.entries[index].kind.candidate(part.1)))
  }
  self.render_node(0, replacements, vars)
}

///|
pub fn CompiledRequest::render_path(
  self : CompiledRequest,
  path : String,
) -> Bytes raise ModelError {
  self.render_node(self.resolve(path), [], None)
}

///|
/// Legacy flat fields receive stable names field0, field1, ... under name.
pub fn CompiledRequest::from_request(
  name : String,
  request : Request,
  max_bytes? : Int = 1048576,
) -> CompiledRequest raise ModelError {
  let children = request.fields.mapi(fn(i, field) {
    Leaf("field\{i}", Field::simple(field.default_value(), field.mutations()))
  })
  CompiledRequest::compile(Block::new(name, children), max_bytes~)
}
