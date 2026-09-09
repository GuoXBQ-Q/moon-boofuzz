///|
/// Named protocol items. Names are one path segment and cannot contain dots.
pub(all) enum Node {
  Leaf(String, Field)
  Nested(Block)
  Repeat(String, String, Int, Int, Int)
  Sized(String, SizeSpec)
}

///|
pub struct Block {
  name : String
  children : Array[Node]
  condition : Condition?
  alignment : (Int, Bytes)?
}

///|
pub fn Block::new(name : String, children : Array[Node]) -> Block {
  { name, children: children.copy(), condition: None, alignment: None, }
}

///|
priv enum EntryKind {
  Atom(Field)
  Container(Array[Int])
  Repetition(String, Int, Int, Int)
  ComputedSize(SizeSpec)
}

///|
struct Entry {
  path : String
  parent : Int?
  kind : EntryKind
  condition : Condition?
  alignment : (Int, Bytes)?
}

///|
pub struct CompiledRequest {
  name : String
  entries : Array[Entry]
  paths : Map[String, Int]
  max_bytes : Int
}

///|
fn valid_name(name : String) -> Bool {
  !name.is_empty() && !name.contains(".") && !name.contains("/")
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
    Leaf(name, _) | Repeat(name, _, _, _, _) | Sized(name, _) => name
    Nested(block) => block.name
  }
  guard valid_name(name) else { raise Invalid("invalid name: " + name) }
  let path = if prefix.is_empty() { name } else { prefix + "." + name }
  guard !paths.contains(path) else { raise Invalid("duplicate path: " + path) }
  let index = entries.length()
  paths[path] = index
  let kind = match node {
    Leaf(_, field) => Atom(field)
    Nested(_) => Container([])
    Sized(_, spec) => ComputedSize(spec)
    Repeat(_, target, min, max, step) => {
      guard min >= 0 && max >= min && step > 0 else {
        raise Invalid("invalid repeat range or step")
      }
      guard (max - min) / step < 2147483647 else {
        raise Invalid("repeat count overflow")
      }
      Repetition(target, min, max, step)
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
  entries.push({ path, parent, kind, condition, alignment, })
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
  let request = { name: root.name, entries, paths, max_bytes, }
  for entry in entries {
    if entry.kind is Repetition(path, _, _, _) {
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
      guard entries[target].kind is Atom(_) else {
        raise Invalid("condition target must be a field")
      }
    }
  }
  request.validate_sizes()
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
fn CompiledRequest::render_node(
  self : CompiledRequest,
  index : Int,
  replacement : (Int, Bytes)?,
) -> Bytes raise ModelError {
  guard self.is_visible(index, replacement) else { return b"" }
  if replacement is Some((target, value)) &&
    target == index &&
    !(self.entries[index].kind is Repetition(_, _, _, _)) {
    guard value.length() <= self.max_bytes else {
      raise Limit("request byte limit: " + self.entries[index].path)
    }
    return value
  }
  match self.entries[index].kind {
    ComputedSize(spec) => self.size_value(spec, replacement)
    Repetition(path, _, _, _) => {
      let count = if replacement is Some((id, value)) && id == index {
        decode_repeat(value)
      } else {
        0
      }
      let bytes = self.render_node(self.resolve(path), replacement)
      guard bytes.is_empty() || count <= self.max_bytes / bytes.length() else {
        raise Limit("repeated block exceeds byte limit")
      }
      bytes.repeat(count)
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
        let bytes = self.render_node(child, replacement)
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
  self.render_node(0, None)
}

///|
pub fn CompiledRequest::render_path(
  self : CompiledRequest,
  path : String,
) -> Bytes raise ModelError {
  self.render_node(self.resolve(path), None)
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
