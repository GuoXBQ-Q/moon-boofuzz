// SPDX-License-Identifier: GPL-2.0-only
// MT19937 and the Python random module semantics needed by the upstream
// RandomData and Float primitives at 518c13904fc32e7f2cc88c9dec934e509062953e
// (boofuzz/primitives/random_data.py, float.py). Integer seeds follow
// CPython's random_seed: the absolute value is split into 32-bit chunks and
// passed to init_by_array (an empty key becomes [0]).

///|
priv struct Mt19937 {
  state : Array[UInt]
  mut index : Int
}

///|
fn Mt19937::make(key : Array[UInt]) -> Mt19937 {
  let state = Array::make(624, 0U)
  state[0] = 19650218U
  for i in 1..<624 {
    let previous = state[i - 1]
    state[i] = (
        1812433253U * (previous ^ (previous >> 30)) + i.reinterpret_as_uint()
      ) &
      0xffffffffU
  }
  let mut i = 1
  let mut j = 0
  let mut k = if key.length() > 624 { key.length() } else { 624 }
  while k > 0 {
    let previous = state[i - 1]
    state[i] = (state[i] ^ ((previous ^ (previous >> 30)) * 1664525U)) +
      key[j] +
      j.reinterpret_as_uint()
    i += 1
    j += 1
    if i >= 624 {
      state[0] = state[623]
      i = 1
    }
    if j >= key.length() {
      j = 0
    }
    k -= 1
  }
  k = 623
  while k > 0 {
    let previous = state[i - 1]
    state[i] = (state[i] ^ ((previous ^ (previous >> 30)) * 1566083941U)) -
      i.reinterpret_as_uint()
    i += 1
    if i >= 624 {
      state[0] = state[623]
      i = 1
    }
    k -= 1
  }
  state[0] = 0x80000000U
  { state, index: 624, }
}

///|
/// Seed like CPython random.seed(int): 32-bit little-endian chunks of the
/// absolute value; a zero seed yields the [0] key.
fn Mt19937::from_seed(seed : Int64) -> Mt19937 raise ModelError {
  guard seed >= 0L else { raise Invalid("random seed must be non-negative") }
  let key : Array[UInt] = []
  let mut remaining = seed.reinterpret_as_uint64()
  while remaining != 0UL {
    key.push(remaining.to_uint())
    remaining = remaining >> 32
  }
  if key.is_empty() {
    key.push(0U)
  }
  Mt19937::make(key)
}

///|
fn Mt19937::next(self : Mt19937) -> UInt {
  if self.index >= 624 {
    for i in 0..<624 {
      let y = (self.state[i] & 0x80000000U) |
        (self.state[(i + 1) % 624] & 0x7fffffffU)
      self.state[i] = self.state[(i + 397) % 624] ^ (y >> 1)
      if (y & 1U) != 0U {
        self.state[i] = self.state[i] ^ 0x9908b0dfU
      }
    }
    self.index = 0
  }
  let mut y = self.state[self.index]
  self.index += 1
  y = y ^ (y >> 11)
  y = y ^ ((y << 7) & 0x9d2c5680U)
  y = y ^ ((y << 15) & 0xefc60000U)
  y ^ (y >> 18)
}

///|
fn Mt19937::getrandbits(self : Mt19937, k : Int) -> UInt64 raise ModelError {
  guard k > 0 && k <= 64 else {
    raise Invalid("getrandbits width out of range")
  }
  let words = (k - 1) / 32 + 1
  let mut result : UInt64 = 0UL
  let mut remaining = k
  for i in 0..<words {
    let mut word = self.next()
    if remaining < 32 {
      word = word >> (32 - remaining)
    }
    result = result | (word.to_uint64() << (32 * i))
    remaining -= 32
  }
  result
}

///|
/// CPython random.random(): 53-bit precision from two tempered words.
fn Mt19937::random(self : Mt19937) -> Double {
  let a = (self.next() >> 5).to_double()
  let b = (self.next() >> 6).to_double()
  (a * 67108864.0 + b) / 9007199254740992.0
}

///|
/// CPython random.uniform(a, b): a + (b - a) * random().
fn Mt19937::uniform(self : Mt19937, low : Double, high : Double) -> Double {
  low + (high - low) * self.random()
}

///|
fn int_bit_length(value : Int) -> Int {
  let mut bits = 0
  let mut remaining = value
  while remaining > 0 {
    bits += 1
    remaining = remaining >> 1
  }
  bits
}

///|
/// CPython random.randint(a, b): randrange with _randbelow_with_getrandbits
/// rejection sampling at k = n.bit_length().
fn Mt19937::randint(
  self : Mt19937,
  low : Int,
  high : Int,
) -> Int raise ModelError {
  guard low <= high else { raise Invalid("empty randint range") }
  let width = high - low + 1
  let k = int_bit_length(width)
  let mut value = self.getrandbits(k).to_int()
  while value >= width {
    value = self.getrandbits(k).to_int()
  }
  low + value
}
