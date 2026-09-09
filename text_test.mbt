///|
test "UTF-8 fields report byte lengths and support disabling" {
  let text = @moon_boofuzz.Field::text("协议", fuzzable=false)
  assert_eq(text.default_value(), b"\xe5\x8d\x8f\xe8\xae\xae")
  assert_eq(text.default_value().length(), 6)
  assert_eq(text.num_mutations(), 0)
  let delimiter = @moon_boofuzz.Field::delimiter("：", fuzzable=false)
  assert_eq(delimiter.default_value().length(), 3)
  assert_eq(delimiter.num_mutations(), 0)
}
