///|
pub struct ChecksumSpec {
  target : String
  endian : Endian
  mutations : Array[Bytes]
  algorithm : ChecksumAlgorithm
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
  algorithm? : ChecksumAlgorithm = Crc32,
) -> Node raise ModelError {
  // Upstream seeds a fuzzable checksum with six fixed byte boundaries of
  // the algorithm's length (boofuzz/blocks/checksum.py:91-98, 518c139);
  // explicit values replace them. MD5/SHA-1 digests exceed 64 bits, so
  // explicit UInt mutations only apply to the 32-bit family.
  let length = algorithm.length()
  guard !(length > 4 && !mutations.is_empty()) else {
    raise Invalid("explicit mutations are not supported for md5/sha1")
  }
  let selected : Array[Bytes] = if !fuzzable {
    []
  } else if mutations.is_empty() {
    [
      Bytes::makei(length, _ => 0x00),
      Bytes::makei(length, _ => 0x11),
      Bytes::makei(length, _ => 0xee),
      Bytes::makei(length, _ => 0xff),
      Bytes::makei(length, fn(i) { if i == length - 1 { 0xfe } else { 0xff } }),
      Bytes::makei(length, fn(i) { if i == length - 1 { 0x01 } else { 0x00 } }),
    ]
  } else {
    mutations.map(value => encode_integer(value.to_uint64(), 32, endian))
  }
  Checksummed(name, { target, endian, mutations: selected, algorithm, })
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

///|
/// RFC 1071 ones' complement sum over 16-bit big-endian words; an odd
/// trailing byte is padded with zero, matching upstream helpers.
fn ones_complement_sum(bytes : Bytes) -> UInt {
  let mut total = 0UL
  let mut i = 0
  let length = bytes.length()
  while i + 1 < length {
    total = total + ((bytes[i].to_uint64() << 8) | bytes[i + 1].to_uint64())
    i += 2
  }
  if i < length {
    total = total + (bytes[i].to_uint64() << 8)
  }
  while total >> 16 != 0UL {
    total = (total & 0xffffUL) + (total >> 16)
  }
  total.to_uint()
}

///|
/// IPv4 header checksum over the header bytes with the checksum field zero;
/// the result is already complemented (0xb861 for the RFC 1071 example).
pub fn ipv4_checksum(header : Bytes) -> UInt {
  ones_complement_sum(header).reinterpret_as_int().lnot().reinterpret_as_uint() &
  0xffffU
}

///|
/// UDP checksum over the pseudo-header plus the UDP header and payload.
/// `source`/`destination` are the 4-byte IPv4 addresses of the pseudo
/// header; `length` is the UDP length field (header + payload). The
/// complemented sum is computed over the same layout as upstream
/// helpers.udp_checksum; an all-zero result is transmitted as 0xffff.
pub fn udp_checksum(
  source : Bytes,
  destination : Bytes,
  udp_bytes : Bytes,
) -> UInt {
  let buffer : Array[Byte] = []
  for byte in source {
    buffer.push(byte)
  }
  for byte in destination {
    buffer.push(byte)
  }
  buffer.push(0)
  buffer.push(17)
  let udp_length = udp_bytes.length()
  buffer.push(((udp_length >> 8) & 255).to_byte())
  buffer.push((udp_length & 255).to_byte())
  for byte in udp_bytes {
    buffer.push(byte)
  }
  if buffer.length() % 2 == 1 {
    buffer.push(0)
  }
  let total = ones_complement_sum(Bytes::from_array(buffer))
  let complement = total.reinterpret_as_int().lnot().reinterpret_as_uint() &
    0xffffU
  if complement == 0U {
    0xffffU
  } else {
    complement
  }
}

///|
/// Checksum algorithms supported by checksum nodes. MD5/SHA-1 render with
/// upstream's 32-bit word swap when the node endianness is big
/// (boofuzz/blocks/checksum.py:171-189, 518c139).
pub(all) enum ChecksumAlgorithm {
  Crc32
  Crc32c
  Adler32
  Md5
  Sha1
} derive(Debug, Eq)

///|
fn ChecksumAlgorithm::length(self : ChecksumAlgorithm) -> Int {
  match self {
    Crc32 | Crc32c | Adler32 => 4
    Md5 => 16
    Sha1 => 20
  }
}

///|
/// Standard digest bytes: the CRC family packs its 32-bit value
/// little-endian; MD5 is little-endian words and SHA-1 big-endian words.
fn ChecksumAlgorithm::digest(self : ChecksumAlgorithm, bytes : Bytes) -> Bytes {
  match self {
    Crc32 => encode_integer(crc32(bytes).to_uint64(), 32, Little)
    Crc32c => encode_integer(crc32c(bytes).to_uint64(), 32, Little)
    Adler32 => encode_integer(adler32(bytes).to_uint64(), 32, Little)
    Md5 => md5(bytes)
    Sha1 => sha1(bytes)
  }
}

///|
/// Render the digest for the node: a big-endian node swaps each 32-bit
/// word of the standard digest (upstream reads the digest as little-endian
/// words and repacks them big-endian); little-endian keeps it verbatim.
/// The result is truncated to the algorithm length.
fn ChecksumAlgorithm::render(
  self : ChecksumAlgorithm,
  bytes : Bytes,
  endian : Endian,
) -> Bytes {
  let standard = self.digest(bytes)
  let digest = if endian is Big {
    let swapped : Array[Byte] = []
    let words = standard.length() / 4
    for w in 0..<words {
      for b in 0..<4 {
        swapped.push(standard[w * 4 + (3 - b)])
      }
    }
    Bytes::from_array(swapped)
  } else {
    standard
  }
  digest[:self.length()].to_owned()
}

///|
