// SPDX-License-Identifier: GPL-2.0-only
// CPython-pinned expectations for the "%.Nf" subset of Field::float
// (upstream float.py renders via "%" + s_format at 518c139).

///|
test "bare f format uses CPython's default precision of six" {
  // "%f" % 42.0 == "42.000000"; the first candidate is the formatted
  // default value.
  let field = @moon_boofuzz.Field::float(
    default_value=42.0,
    s_format="f",
    max_mutations=1,
  )
  assert_eq(field.mutation(0), Some(b"42.000000"))
}

///|
test "fixed point rounds the exact binary value not a scaled double" {
  // "%.1f" % 0.05 == "0.1": the double is strictly above the decimal
  // midpoint, which scale-by-ten then ties-to-even used to lose ("0.0").
  let above = @moon_boofuzz.Field::float(
    default_value=0.05,
    s_format=".1f",
    max_mutations=1,
  )
  assert_eq(above.mutation(0), Some(b"0.1"))
  // "%.2f" % 2.675 == "2.67": the double is strictly below the midpoint.
  let below = @moon_boofuzz.Field::float(
    default_value=2.675,
    s_format=".2f",
    max_mutations=1,
  )
  assert_eq(below.mutation(0), Some(b"2.67"))
  // Exact midpoints round half-to-even: "%.1f" % 0.25 == "0.2".
  let tie_even = @moon_boofuzz.Field::float(
    default_value=0.25,
    s_format=".1f",
    max_mutations=1,
  )
  assert_eq(tie_even.mutation(0), Some(b"0.2"))
  // "%.0f" % 0.5 == "0" and "%.0f" % 1.5 == "2".
  let zero_digits = @moon_boofuzz.Field::float(
    default_value=0.5,
    s_format=".0f",
    max_mutations=1,
  )
  assert_eq(zero_digits.mutation(0), Some(b"0"))
  let one_five = @moon_boofuzz.Field::float(
    default_value=1.5,
    s_format=".0f",
    max_mutations=1,
  )
  assert_eq(one_five.mutation(0), Some(b"2"))
  // Negative magnitudes keep the sign: "%.1f" % -0.05 == "-0.1".
  let negative = @moon_boofuzz.Field::float(
    default_value=-0.05,
    s_format=".1f",
    max_mutations=1,
  )
  assert_eq(negative.mutation(0), Some(b"-0.1"))
}

///|
test "fixed point handles wide exponents exact ties and carry" {
  fn first(field : @moon_boofuzz.Field) -> Bytes? {
    field.mutation(0)
  }
  // 10^21 is exactly representable (2^21 * 5^21, 5^21 < 2^53): the big
  // integer path prints every digit, like CPython.
  let exact_big = @moon_boofuzz.Field::float(
    default_value=1000000000000000000000.0,
    s_format=".1f",
    max_mutations=1,
  )
  assert_eq(first(exact_big), Some(b"1000000000000000000000.0"))
  // The double nearest 0.1 is 0.1000000000000000055511151231257827...
  // exactly; %.20f prints the exact expansion, not 0.10000000000000000000.
  let expansion = @moon_boofuzz.Field::float(
    default_value=0.1,
    s_format=".20f",
    max_mutations=1,
  )
  assert_eq(first(expansion), Some(b"0.10000000000000000555"))
  // Trailing zeros fill exact values: "%.30f" % 2.5.
  let padded = @moon_boofuzz.Field::float(
    default_value=2.5,
    s_format=".30f",
    max_mutations=1,
  )
  assert_eq(first(padded), Some(b"2.500000000000000000000000000000"))
  // Exact integer ties round half-to-even: "%.0f" % 2.5 == "2",
  // "%.0f" % 3.5 == "4".
  let tie_down = @moon_boofuzz.Field::float(
    default_value=2.5,
    s_format=".0f",
    max_mutations=1,
  )
  assert_eq(first(tie_down), Some(b"2"))
  let tie_up = @moon_boofuzz.Field::float(
    default_value=3.5,
    s_format=".0f",
    max_mutations=1,
  )
  assert_eq(first(tie_up), Some(b"4"))
  // Rounding carries across decimal digits: "%.1f" % 9.99 == "10.0".
  let carry = @moon_boofuzz.Field::float(
    default_value=9.99,
    s_format=".1f",
    max_mutations=1,
  )
  assert_eq(first(carry), Some(b"10.0"))
}

///|
test "float format specifiers outside the subset are rejected" {
  for bad in ["d", ".2e", "10f", ".2g", "f2", ".-1f", ""] {
    let rejected = try {
      ignore(
        @moon_boofuzz.Field::float(
          default_value=1.0,
          s_format=bad,
          max_mutations=1,
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "float default renders through the same formatting" {
  // Upstream seeds BitField with str(default_value) ("2.5"), while the
  // first mutation is the s_format rendering ("2.50"); both feed prefix
  // requests and the fuzz stream respectively.
  let field = @moon_boofuzz.Field::float(
    default_value=2.5,
    s_format=".2f",
    max_mutations=1,
    fuzzable=false,
  )
  assert_eq(field.default_value(), b"2.5")
  assert_eq(field.num_mutations(), 0)
}
