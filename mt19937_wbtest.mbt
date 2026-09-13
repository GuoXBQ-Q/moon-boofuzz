// Reference values probed from CPython 3.12.3 (the development oracle):
//   random.Random(0).randint(0,255) x12, randint(0,10) x6,
//   random.Random(12345).randint(0,255) x8, Random(0).getrandbits([8,16,32,33,1]).

///|
test "mt19937 randint matches CPython" {
  let generator = Mt19937::from_seed(0)
  let expected : Array[Int] = [
    197, 215, 20, 132, 248, 207, 155, 244, 183, 111, 71, 144,
  ]
  for value in expected {
    assert_eq(generator.randint(0, 255), value)
  }
}

///|
test "mt19937 small range matches CPython" {
  let generator = Mt19937::from_seed(0)
  let expected : Array[Int] = [6, 6, 0, 4, 8, 7]
  for value in expected {
    assert_eq(generator.randint(0, 10), value)
  }
}

///|
test "mt19937 nonzero seed matches CPython" {
  let generator = Mt19937::from_seed(12345)
  let expected : Array[Int] = [213, 5, 152, 188, 99, 138, 223, 82]
  for value in expected {
    assert_eq(generator.randint(0, 255), value)
  }
}

///|
test "mt19937 getrandbits matches CPython" {
  let generator = Mt19937::from_seed(0)
  assert_eq(generator.getrandbits(8), 216UL)
  assert_eq(generator.getrandbits(16), 25247UL)
  assert_eq(generator.getrandbits(32), 3255389356UL)
  assert_eq(generator.getrandbits(33), 3823568514UL)
  assert_eq(generator.getrandbits(1), 0UL)
}

///|
test "mt19937 uniform matches CPython" {
  let generator = Mt19937::from_seed(0)
  let first = generator.uniform(0.0, 100.0)
  assert_eq(first, 84.4421851525048)
  let second = generator.uniform(0.0, 100.0)
  assert_eq(second, 75.79544029403024)
}
