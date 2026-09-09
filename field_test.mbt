///|
test "simple snapshots candidates and preserves binary duplicates" {
  let values = [b"", b"\x00\xff", b"\x00\xff"]
  let field = @moon_boofuzz.Field::simple(b"default", values)
  values[0] = b"changed"
  assert_eq(field.default_value(), b"default")
  assert_eq(field.num_mutations(), 3)
  assert_eq(field.mutation(0), Some(b""))
  assert_eq(field.mutation(1), Some(b"\x00\xff"))
  assert_eq(field.mutation(2), Some(b"\x00\xff"))
  assert_eq(field.mutation(-1), None)
  assert_eq(field.mutation(3), None)
  assert_eq(@moon_boofuzz.Field::simple(b"", []).num_mutations(), 0)
  assert_eq(
    @moon_boofuzz.Field::simple(b"A", values, fuzzable=false).num_mutations(),
    0,
  )
}

///|
test "group removes exactly one default and snapshots input" {
  let values = [b"A", b"B", b"A", b"B"]
  let field = @moon_boofuzz.Field::group(values)
  values.clear()
  assert_eq(field.default_value(), b"A")
  assert_eq(field.num_mutations(), 3)
  assert_eq(field.mutation(0), Some(b"B"))
  assert_eq(field.mutation(1), Some(b"A"))
  assert_eq(field.mutation(2), Some(b"B"))
  let explicit = @moon_boofuzz.Field::group(
    [b"A", b"B", b"B"],
    default_value=b"B",
  )
  assert_eq(explicit.default_value(), b"B")
  assert_eq(explicit.num_mutations(), 2)
  assert_eq(explicit.mutation(0), Some(b"A"))
  assert_eq(explicit.mutation(1), Some(b"B"))
  let absent = @moon_boofuzz.Field::group([b"A"], default_value=b"C")
  assert_eq(absent.default_value(), b"C")
  assert_eq(absent.mutation(0), Some(b"A"))
  assert_eq(@moon_boofuzz.Field::group([b"A"]).num_mutations(), 0)
  let disabled = @moon_boofuzz.Field::group([b"A", b"B"], fuzzable=false)
  assert_eq(disabled.default_value(), b"A")
  assert_eq(disabled.num_mutations(), 0)
  assert_eq(disabled.mutation(0), None)
}

///|
test "empty group returns typed model error" {
  let rejected = try {
    ignore(@moon_boofuzz.Field::group([]))
    false
  } catch {
    @moon_boofuzz.ModelError::Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}
