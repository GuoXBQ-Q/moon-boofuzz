///|
pub struct ChecksumSpec {
  target : String
  endian : Endian
  mutations : Array[Bytes]
}

///|
/// Reflected IEEE CRC32, initial/final XOR 0xffffffff, polynomial 0xedb88320.
pub fn crc32(bytes : Bytes) -> UInt {
  let mut crc = 0xffffffffU
  for byte in bytes {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = if (crc & 1U) != 0U { (crc >> 1) ^ 0xedb88320U } else { crc >> 1 }
    }
  }
  crc ^ 0xffffffffU
}

///|
pub fn Node::checksum(
  name : String,
  target : String,
  endian? : Endian = Little,
  mutations? : Array[UInt] = [],
  fuzzable? : Bool = true,
) -> Node {
  // Upstream seeds a fuzzable checksum with six fixed byte boundaries
  // (boofuzz/blocks/checksum.py:91-98, 518c139); explicit values replace them.
  let selected : Array[Bytes] = if !fuzzable {
    []
  } else if mutations.is_empty() {
    [
      b"\x00\x00\x00\x00", b"\x11\x11\x11\x11", b"\xee\xee\xee\xee", b"\xff\xff\xff\xff",
      b"\xff\xff\xff\xfe", b"\x00\x00\x00\x01",
    ]
  } else {
    mutations.map(value => encode_integer(value.to_uint64(), 32, endian))
  }
  Checksummed(name, { target, endian, mutations: selected, })
}

///|
fn CompiledRequest::checksum_dependencies(
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
    ComputedChecksum(_) => output.push(index)
    Container(children) =>
      for child in children {
        self.checksum_dependencies(child, output, visited)
      }
    Repetition(path, _, _, _, _) =>
      self.checksum_dependencies(self.resolve(path), output, visited)
    Dynamic(_, _) | Atom(_) | ComputedSize(_) | Mirror(_) => ()
  }
}

///|
fn CompiledRequest::validate_checksums(
  self : CompiledRequest,
) -> Unit raise ModelError {
  let edges : Array[Array[Int]] = Array::makei(self.entries.length(), _ => [])
  for i, entry in self.entries {
    if entry.kind is ComputedChecksum(spec) {
      let target = self.resolve(spec.target)
      guard self.entries[target].kind is Container(_) else {
        raise Invalid("checksum target must be a block")
      }
      let dependencies : Array[Int] = []
      self.checksum_dependencies(
        target,
        dependencies,
        Array::make(self.entries.length(), false),
      )
      for dependency in dependencies {
        if dependency != i {
          edges[i].push(dependency)
        } else {
          guard entry.path.has_prefix(spec.target + ".") else {
            raise Invalid("indirect checksum self dependency")
          }
        }
      }
    }
  }
  let states = Array::make(self.entries.length(), 0)
  for i in 0..<self.entries.length() {
    visit_dependencies(i, edges, states, 0)
  }
}

///|
/// Adler-32 (RFC 1950): two 16-bit sums modulo 65521, matching zlib.
pub fn adler32(bytes : Bytes) -> UInt {
  let mut a = 1U
  let mut b = 0U
  for byte in bytes {
    a = (a + byte.to_uint()) % 65521U
    b = (b + a) % 65521U
  }
  (b << 16) | a
}

///|
/// CRC-32C (Castagnoli, poly 0x82F63B78 reflected), initial/final XOR
/// 0xffffffff — the algorithm behind upstream's optional crc32c dependency.
pub fn crc32c(bytes : Bytes) -> UInt {
  let mut crc = 0xffffffffU
  for byte in bytes {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = if (crc & 1U) != 0U { (crc >> 1) ^ 0x82f63b78U } else { crc >> 1 }
    }
  }
  crc ^ 0xffffffffU
}
