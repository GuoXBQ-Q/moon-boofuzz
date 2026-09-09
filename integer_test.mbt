///|
test "integer endian encoding and unsigned upper limit" {
  let be = @moon_boofuzz.Field::integer(0x12345678UL, width=32, endian=Big)
  let le = @moon_boofuzz.Field::integer(0x12345678UL, width=32)
  assert_eq(be.default_value(), b"\x12\x34\x56\x78")
  assert_eq(le.default_value(), b"\x78\x56\x34\x12")
  let maximum = @moon_boofuzz.Field::integer(0xffffffffffffffffUL, width=64)
  assert_eq(maximum.default_value(), b"\xff\xff\xff\xff\xff\xff\xff\xff")
  assert_eq(
    maximum.mutation(maximum.num_mutations() - 1),
    Some(maximum.default_value()),
  )
  assert_eq(
    @moon_boofuzz.Field::integer(0UL, fuzzable=false).num_mutations(),
    0,
  )
}

///|
test "integer invalid widths and out of range defaults" {
  for width in [0, -1, 1, 7, 9, 24, 65] {
    assert_true(
      try {
        ignore(@moon_boofuzz.Field::integer(0UL, width~))
        false
      } catch {
        @moon_boofuzz.ModelError::Invalid(_) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      ignore(@moon_boofuzz.Field::integer(256UL))
      false
    } catch {
      @moon_boofuzz.ModelError::Invalid(_) => true
      _ => false
    },
  )
}
