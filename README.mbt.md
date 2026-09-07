# Tested API example

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
