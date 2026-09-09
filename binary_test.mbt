///|
test "binary default is not truncated and invalid sizes are rejected" {
  let field = @moon_boofuzz.Field::binary(b"ABC", size=1)
  assert_eq(field.default_value(), b"ABC")
  assert_eq(field.mutation(0), Some(b"\x00"))
  assert_eq(@moon_boofuzz.Field::binary(b"", fuzzable=false).num_mutations(), 0)
  assert_true(
    try {
      ignore(@moon_boofuzz.Field::binary(b"", size=-1))
      false
    } catch {
      @moon_boofuzz.ModelError::Invalid(_) => true
    },
  )
  assert_true(
    try {
      ignore(@moon_boofuzz.Field::binary(b"", padding=b"AB"))
      false
    } catch {
      @moon_boofuzz.ModelError::Invalid(_) => true
    },
  )
}
