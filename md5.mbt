// SPDX-License-Identifier: GPL-2.0-only
// MD5 (RFC 1321) and SHA-1 (RFC 3174) digests, ported for the checksum
// algorithm set of boofuzz/blocks/checksum.py at 518c139. Pure core; only
// the digest bytes are produced — the big-endian word swap upstream applies
// to md5/sha1 happens in the checksum node rendering.

///|
/// MD5 digest (16 bytes) of the input.
pub fn md5(message : Bytes) -> Bytes {
  // Padding: 0x80, zeros, 64-bit little-endian bit length.
  let bit_length = message.length().to_int64() * 8L
  let padded = message.length() +
    1 +
    ((55 - message.length()) % 64 + 64) % 64 +
    8
  let buffer : Array[Byte] = []
  for byte in message {
    buffer.push(byte)
  }
  buffer.push(0x80)
  while buffer.length() % 64 != 56 {
    buffer.push(0)
  }
  for i in 0..<8 {
    buffer.push(((bit_length >> (i * 8)) & 0xffL).to_byte())
  }
  ignore(padded)
  let mut a0 = 0x67452301U
  let mut b0 = 0xefcdab89U
  let mut c0 = 0x98badcfeU
  let mut d0 = 0x10325476U
  let shifts : Array[Int] = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5,
    9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16,
    23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ]
  let constants : Array[UInt] = [
    0xd76aa478U, 0xe8c7b756U, 0x242070dbU, 0xc1bdceeeU, 0xf57c0fafU, 0x4787c62aU,
    0xa8304613U, 0xfd469501U, 0x698098d8U, 0x8b44f7afU, 0xffff5bb1U, 0x895cd7beU,
    0x6b901122U, 0xfd987193U, 0xa679438eU, 0x49b40821U, 0xf61e2562U, 0xc040b340U,
    0x265e5a51U, 0xe9b6c7aaU, 0xd62f105dU, 0x02441453U, 0xd8a1e681U, 0xe7d3fbc8U,
    0x21e1cde6U, 0xc33707d6U, 0xf4d50d87U, 0x455a14edU, 0xa9e3e905U, 0xfcefa3f8U,
    0x676f02d9U, 0x8d2a4c8aU, 0xfffa3942U, 0x8771f681U, 0x6d9d6122U, 0xfde5380cU,
    0xa4beea44U, 0x4bdecfa9U, 0xf6bb4b60U, 0xbebfbc70U, 0x289b7ec6U, 0xeaa127faU,
    0xd4ef3085U, 0x04881d05U, 0xd9d4d039U, 0xe6db99e5U, 0x1fa27cf8U, 0xc4ac5665U,
    0xf4292244U, 0x432aff97U, 0xab9423a7U, 0xfc93a039U, 0x655b59c3U, 0x8f0ccc92U,
    0xffeff47dU, 0x85845dd1U, 0x6fa87e4fU, 0xfe2ce6e0U, 0xa3014314U, 0x4e0811a1U,
    0xf7537e82U, 0xbd3af235U, 0x2ad7d2bbU, 0xeb86d391U,
  ]
  for chunk in 0..<(buffer.length() / 64) {
    let words : Array[UInt] = Array::make(16, 0U)
    for w in 0..<16 {
      let mut value = 0U
      for b in 0..<4 {
        value = value | (buffer[chunk * 64 + w * 4 + b].to_uint() << (b * 8))
      }
      words[w] = value
    }
    let mut a = a0
    let mut b = b0
    let mut c = c0
    let mut d = d0
    for i in 0..<64 {
      let (f, g) = match i {
        0..<16 =>
          (
            (b & c) | (b.reinterpret_as_int().lnot().reinterpret_as_uint() & d),
            i,
          )
        16..<32 =>
          (
            (d & b) | (d.reinterpret_as_int().lnot().reinterpret_as_uint() & c),
            (5 * i + 1) % 16,
          )
        32..<48 => (b ^ c ^ d, (3 * i + 5) % 16)
        _ =>
          (
            c ^ (b | d.reinterpret_as_int().lnot().reinterpret_as_uint()),
            7 * i % 16,
          )
      }
      let f2 = f + a + constants[i] + words[g]
      a = d
      d = c
      c = b
      let shift = shifts[i]
      b = b + ((f2 << shift) | (f2 >> (32 - shift)))
    }
    a0 = a0 + a
    b0 = b0 + b
    c0 = c0 + c
    d0 = d0 + d
  }
  digest_bytes([a0, b0, c0, d0], Little)
}

///|
/// SHA-1 digest (20 bytes) of the input.
pub fn sha1(message : Bytes) -> Bytes {
  let bit_length = message.length().to_int64() * 8L
  let buffer : Array[Byte] = []
  for byte in message {
    buffer.push(byte)
  }
  buffer.push(0x80)
  while buffer.length() % 64 != 56 {
    buffer.push(0)
  }
  for i in 0..<8 {
    buffer.push(((bit_length >> (56 - i * 8)) & 0xffL).to_byte())
  }
  let mut h0 = 0x67452301U
  let mut h1 = 0xefcdab89U
  let mut h2 = 0x98badcfeU
  let mut h3 = 0x10325476U
  let mut h4 = 0xc3d2e1f0U
  for chunk in 0..<(buffer.length() / 64) {
    let words : Array[UInt] = Array::make(80, 0U)
    for w in 0..<16 {
      let mut value = 0U
      for b in 0..<4 {
        value = (value << 8) | buffer[chunk * 64 + w * 4 + b].to_uint()
      }
      words[w] = value
    }
    for w in 16..<80 {
      let mixed = words[w - 3] ^ words[w - 8] ^ words[w - 14] ^ words[w - 16]
      words[w] = (mixed << 1) | (mixed >> 31)
    }
    let mut a = h0
    let mut b = h1
    let mut c = h2
    let mut d = h3
    let mut e = h4
    for i in 0..<80 {
      let (f, k) = match i {
        0..<20 =>
          (
            (b & c) | (b.reinterpret_as_int().lnot().reinterpret_as_uint() & d),
            0x5a827999U,
          )
        20..<40 => (b ^ c ^ d, 0x6ed9eba1U)
        40..<60 => ((b & c) | (b & d) | (c & d), 0x8f1bbcdcU)
        _ => (b ^ c ^ d, 0xca62c1d6U)
      }
      let rotated = (a << 5) | (a >> 27)
      let temp = rotated + f + e + k + words[i]
      e = d
      d = c
      c = (b << 30) | (b >> 2)
      b = a
      a = temp
    }
    h0 = h0 + a
    h1 = h1 + b
    h2 = h2 + c
    h3 = h3 + d
    h4 = h4 + e
  }
  digest_bytes([h0, h1, h2, h3, h4], Big)
}

///|
priv enum WordOrder {
  Little
  Big
}

///|
fn digest_bytes(words : Array[UInt], order : WordOrder) -> Bytes {
  let bytes : Array[Byte] = []
  for word in words {
    for i in 0..<4 {
      let shift = match order {
        Little => i * 8
        Big => 24 - i * 8
      }
      bytes.push(((word >> shift) & 255U).to_byte())
    }
  }
  Bytes::from_array(bytes)
}
