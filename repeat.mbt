///|
/// Repeat appends copies of a preceding named block; normal output is empty.
pub fn Node::repeat(
  name : String,
  target : String,
  min? : Int = 0,
  max? : Int = 25,
  step? : Int = 1,
) -> Node {
  Repeat(name, target, min, max, step)
}

///|
fn decode_repeat(bytes : Bytes) -> Int {
  bytes[0].to_int() |
  (bytes[1].to_int() << 8) |
  (bytes[2].to_int() << 16) |
  (bytes[3].to_int() << 24)
}

///|
fn EntryKind::count(self : EntryKind) -> Int {
  match self {
    Atom(field) => field.count
    ComputedSize(spec) => spec.mutations.length()
    Repetition(_, min, max, step) => (max - min) / step + 1
    Container(_) => 0
  }
}

///|
fn EntryKind::candidate(self : EntryKind, index : Int) -> Bytes {
  match self {
    Atom(field) => (field.candidate)(index)
    ComputedSize(spec) => spec.mutations[index]
    Repetition(_, min, _, step) =>
      encode_integer((min + step * index).to_uint64(), 32, Little)
    Container(_) => b""
  }
}
