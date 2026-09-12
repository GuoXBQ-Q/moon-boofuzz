# Tested API example

## Simple and Group

`Field::simple(default, candidates)` preserves every explicit candidate.
`Field::group(values, default_value=...)` selects the first value by default,
then removes only the first matching default from mutation candidates.
Both snapshot input arrays; `fuzzable=false` yields zero cases. Indices are
zero based and out-of-range access returns `None`. Use these fields as named
Leaf nodes in CompiledRequest; the legacy flat Request remains available.

```mbt check
///|
test "group field" {
  let field = @moon_boofuzz.Field::group([b"GET", b"POST", b"GET"])
  assert_eq(field.default_value(), b"GET")
  assert_eq(field.num_mutations(), 2)
  assert_eq(field.mutation(0), Some(b"POST"))
  assert_eq(field.mutation(1), Some(b"GET"))
}
```

```mbt check
///|
test "minimal byte request" {
  let request = @moon_boofuzz.Request::new([
    @moon_boofuzz.Static(b"PING "),
    @moon_boofuzz.Choice(b"ok", [b"", b"long"]),
  ])
  assert_eq(request.render(), b"PING ok")
  assert_eq(request.mutations(), [b"PING ", b"PING long"])
}
```
