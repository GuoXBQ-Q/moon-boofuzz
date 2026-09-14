///|
pub struct SizeSpec {
  target : String
  length : Int
  endian : Endian
  offset : Int
  inclusive : Bool
  mutations : Array[Bytes]
}

///|
pub fn Node::size(
  name : String,
  target : String,
  length? : Int = 4,
  endian? : Endian = Little,
  offset? : Int = 0,
  inclusive? : Bool = false,
  mutations? : Array[UInt64] = [],
  fuzzable? : Bool = true,
) -> Node raise ModelError {
  guard length == 1 || length == 2 || length == 4 || length == 8 else {
    raise Invalid("size length must be 1, 2, 4 or 8 bytes")
  }
  let maximum = integer_max(length * 8)
  // With no explicit values, upstream delegates mutations to an inner
  // BitField over the full width (boofuzz/blocks/size.py:91-104, 518c139);
  // the encoded values then bypass length computation (size.py:106-115).
  let selected : Array[UInt64] = if !fuzzable {
    []
  } else if mutations.is_empty() {
    integer_boundaries(maximum)
  } else {
    for value in mutations {
      guard value <= maximum else {
        raise Invalid("explicit size mutation overflow")
      }
    }
    mutations
  }
  let values = selected.map(value => encode_integer(value, length * 8, endian))
  Sized(name, { target, length, endian, offset, inclusive, mutations: values, })
}

///|
fn CompiledRequest::measure(
  self : CompiledRequest,
  index : Int,
  replacements : Replacements,
  vars : Map[String, Bytes]?,
  active? : Array[Int] = [],
) -> Int raise ModelError {
  guard self.is_visible(index, replacements, vars) else { return 0 }
  let size = match self.entries[index].kind {
    Atom(field) =>
      match replacements.lookup(index) {
        Some(value) => value.length()
        None => field.value.length()
      }
    Dynamic(field, variable) =>
      match replacements.lookup(index) {
        Some(value) => value.length()
        None =>
          match vars {
            Some(map) =>
              match map.get(variable) {
                Some(bytes) => bytes.length()
                None => raise Invalid("missing session variable: " + variable)
              }
            None => field.value.length()
          }
      }
    ComputedSize(spec) => spec.length
    ComputedChecksum(spec) => spec.algorithm.length()
    Mirror(target) => {
      guard !active.contains(index) else { return 0 }
      let nested = active.copy()
      nested.push(index)
      self.measure(self.resolve(target), replacements, vars, active=nested)
    }
    Repetition(path, _, _, _, variable) => {
      let n = match replacements.lookup(index) {
        Some(bytes) => decode_repeat(bytes)
        None =>
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
      let child = self.measure(self.resolve(path), replacements, vars)
      guard child == 0 || n <= self.max_bytes / child else {
        raise Limit("repeated length exceeds byte limit")
      }
      child * n
    }
    Container(children) => {
      let mut total = 0
      for child in children {
        let n = self.measure(child, replacements, vars)
        guard n <= self.max_bytes - total else {
          raise Limit("measured request exceeds byte limit")
        }
        total += n
      }
      if self.entries[index].alignment is Some((modulus, _)) {
        let padding = modulus - total % modulus
        guard padding <= self.max_bytes - total else {
          raise Limit("aligned length exceeds byte limit")
        }
        total += padding
      }
      total
    }
  }
  guard size <= self.max_bytes else {
    raise Limit("field length exceeds byte limit")
  }
  size
}

///|
fn CompiledRequest::size_value(
  self : CompiledRequest,
  spec : SizeSpec,
  replacements : Replacements,
  vars : Map[String, Bytes]?,
) -> Bytes raise ModelError {
  let length = self
    .measure(self.resolve(spec.target), replacements, vars)
    .to_int64() +
    spec.offset.to_int64() +
    (if spec.inclusive { spec.length.to_int64() } else { 0L })
  guard length >= 0L else { raise Invalid("negative computed size") }
  let value = length.reinterpret_as_uint64()
  guard value <= integer_max(spec.length * 8) else {
    raise Invalid("computed size encoding overflow")
  }
  encode_integer(value, spec.length * 8, spec.endian)
}

///|
fn CompiledRequest::size_dependencies(
  self : CompiledRequest,
  index : Int,
  output : Array[Int],
  visited : Array[Bool],
) -> Unit raise ModelError {
  if visited[index] {
    return
  }
  visited[index] = true
  match self.entries[index].kind {
    ComputedSize(_) => output.push(index)
    Container(children) =>
      for child in children {
        self.size_dependencies(child, output, visited)
      }
    Repetition(path, _, _, _, _) =>
      self.size_dependencies(self.resolve(path), output, visited)
    Dynamic(_, _) | Atom(_) | ComputedChecksum(_) | Mirror(_) => ()
  }
}

///|
fn visit_dependencies(
  index : Int,
  edges : Array[Array[Int]],
  states : Array[Int],
  depth : Int,
) -> Unit raise ModelError {
  guard depth <= 256 else {
    raise Invalid("derived dependency depth exceeds 256")
  }
  if states[index] == 2 {
    return
  }
  guard states[index] != 1 else {
    raise Invalid("derived field dependency cycle")
  }
  states[index] = 1
  for target in edges[index] {
    visit_dependencies(target, edges, states, depth + 1)
  }
  states[index] = 2
}

///|
fn CompiledRequest::validate_sizes(
  self : CompiledRequest,
) -> Unit raise ModelError {
  let edges : Array[Array[Int]] = Array::makei(self.entries.length(), _ => [])
  for i, entry in self.entries {
    if entry.kind is ComputedSize(spec) {
      let target = self.resolve(spec.target)
      guard self.entries[target].kind is Container(_) else {
        raise Invalid("size target must be a block")
      }
      let dependencies : Array[Int] = []
      self.size_dependencies(
        target,
        dependencies,
        Array::make(self.entries.length(), false),
      )
      for dependency in dependencies {
        if dependency != i {
          edges[i].push(dependency)
        } else {
          guard entry.path.has_prefix(spec.target + ".") else {
            raise Invalid("indirect self size dependency")
          }
        }
      }
    }
  }
  let states = Array::make(self.entries.length(), 0)
  for i in 0..<self.entries.length() {
    visit_dependencies(i, edges, states, 0)
  }
  for entry in self.entries {
    if entry.kind is ComputedSize(spec) {
      ignore(self.size_value(spec, [], None))
    }
  }
}
