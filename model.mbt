///|
/// Named protocol items. Names are one path segment and cannot contain dots.
pub(all) enum Node {
  Leaf(String, Field)
  Nested(Block)
}

///|
pub struct Block {
  name : String
  children : Array[Node]
}

///|
pub fn Block::new(name : String, children : Array[Node]) -> Block {
  { name, children: children.copy(), }
}

///|
priv enum EntryKind {
  Atom(Field)
  Container(Array[Int])
}

///|
struct Entry {
  path : String
  parent : Int?
  kind : EntryKind
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
    Leaf(name, _) => name
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
  }
  entries.push({ path, parent, kind, })
  if node is Nested(block) {
    let children = block.children.map(child => {
      add_node(child, path, Some(index), entries, paths, depth + 1)
    })
    entries[index] = { path, parent, kind: Container(children), }
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
  if replacement is Some((target, value)) && target == index {
    guard value.length() <= self.max_bytes else {
      raise Limit("request byte limit: " + self.entries[index].path)
    }
    return value
  }
  match self.entries[index].kind {
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
