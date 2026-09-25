// Reference vectors from Python hashlib/zlib (the development oracle).

///|
fn hex_of(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let text : Array[Char] = []
  for byte in bytes {
    let value = byte.to_int()
    text.push(digits[value >> 4].unsafe_to_char())
    text.push(digits[value & 15].unsafe_to_char())
  }
  String::from_array(text)
}

///|
test "md5 reference vectors" {
  assert_eq(hex_of(@moon_boofuzz.md5(b"")), "d41d8cd98f00b204e9800998ecf8427e")
  assert_eq(
    hex_of(@moon_boofuzz.md5(b"abc")),
    "900150983cd24fb0d6963f7d28e17f72",
  )
  assert_eq(
    hex_of(@moon_boofuzz.md5(b"The quick brown fox jumps over the lazy dog")),
    "9e107d9d372bb6826bd81d3542a419d6",
  )
}

///|
test "sha1 reference vectors" {
  assert_eq(
    hex_of(@moon_boofuzz.sha1(b"")),
    "da39a3ee5e6b4b0d3255bfef95601890afd80709",
  )
  assert_eq(
    hex_of(@moon_boofuzz.sha1(b"abc")),
    "a9993e364706816aba3e25717850c26c9cd0d89d",
  )
}

///|
test "adler32 and crc32c reference vectors" {
  // zlib.adler32(b'Wikipedia') == 0x11e60398
  assert_eq(@moon_boofuzz.adler32(b"Wikipedia"), 0x11e60398U)
  // Castagnoli CRC-32C reference: crc32c(b'123456789') == 0xe3069283
  assert_eq(@moon_boofuzz.crc32c(b"123456789"), 0xe3069283U)
  assert_eq(@moon_boofuzz.crc32c(b"hello"), 0x9a71bb4cU)
}

///|
test "ipv4 and udp checksum reference vectors" {
  // RFC 1071 / Wikipedia IPv4 header example with a zero checksum field:
  // 4500 0073 0000 4000 4011 0000 c0a8 0001 c0a8 00c7 -> 0xb861.
  let header = b"\x45\x00\x00\x73\x00\x00\x40\x00\x40\x11\x00\x00\xc0\xa8\x00\x01\xc0\xa8\x00\xc7"
  assert_eq(@moon_boofuzz.ipv4_checksum(header), 0xb861U)
  // Pseudo-header (192.168.0.1 -> 192.168.0.199, proto 17, length 8) over
  // a UDP header {sport 100, dport 0, len 8, csum 0} -> 0x7d61.
  let source = b"\xc0\xa8\x00\x01"
  let destination = b"\xc0\xa8\x00\xc7"
  let udp = b"\x00\x64\x00\x00\x00\x08\x00\x00"
  assert_eq(@moon_boofuzz.udp_checksum(source, destination, udp), 0x7d61U)
}

///|
test "md5 checksum node renders digest with upstream word swap" {
  // Little endian: standard MD5 digest of "abc" verbatim (16 bytes).
  let little = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      @moon_boofuzz.Node::checksum(
        "crc",
        "r.body",
        algorithm=@moon_boofuzz.ChecksumAlgorithm::Md5,
        fuzzable=false,
      ),
      Nested(
        @moon_boofuzz.Block::new("body", [
          Leaf("x", @moon_boofuzz.Field::simple(b"abc", [])),
        ]),
      ),
    ]),
  )
  assert_eq(
    little.render(),
    b"\x90\x01\x50\x98\x3c\xd2\x4f\xb0\xd6\x96\x3f\x7d\x28\xe1\x7f\x72abc",
  )
  // Big endian: upstream repacks the digest words big-endian.
  let big = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      @moon_boofuzz.Node::checksum(
        "crc",
        "r.body",
        endian=Big,
        algorithm=@moon_boofuzz.ChecksumAlgorithm::Md5,
        fuzzable=false,
      ),
      Nested(
        @moon_boofuzz.Block::new("body", [
          Leaf("x", @moon_boofuzz.Field::simple(b"abc", [])),
        ]),
      ),
    ]),
  )
  assert_eq(
    big.render(),
    b"\x98\x50\x01\x90\xb0\x4f\xd2\x3c\x7d\x3f\x96\xd6\x72\x7f\xe1\x28abc",
  )
}

///|
test "sha1 checksum node renders 20-byte digest" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("r", [
      @moon_boofuzz.Node::checksum(
        "crc",
        "r.body",
        algorithm=@moon_boofuzz.ChecksumAlgorithm::Sha1,
      ),
      Nested(
        @moon_boofuzz.Block::new("body", [
          Leaf("x", @moon_boofuzz.Field::simple(b"abc", [])),
        ]),
      ),
    ]),
  )
  assert_eq(request.render().length(), 20 + 3)
  assert_eq(request.raw_mutation_count(), 6L)
}
