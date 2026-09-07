///|
test "binary rendering preserves zero and non-UTF8 bytes" {
  let request = @moon_boofuzz.Request::new([
    @moon_boofuzz.Static(b"\x00\xff"),
    @moon_boofuzz.Choice(b"A", [b"B"]),
  ])
  assert_eq(request.render(), b"\x00\xffA")
}

///|
test "one field changes at a time in deterministic order" {
  let request = @moon_boofuzz.Request::new([
    @moon_boofuzz.Choice(b"A", [b"", b"AA"]),
    @moon_boofuzz.Static(b":"),
    @moon_boofuzz.Choice(b"B", [b"C"]),
  ])
  assert_eq(request.mutations(), [b":B", b"AA:B", b"A:C"])
  assert_eq(request.mutations(), request.mutations())
  assert_eq(request.render(), b"A:B")
}

///|
test "empty and static requests have no mutations" {
  assert_eq(@moon_boofuzz.Request::new([]).render(), b"")
  assert_eq(@moon_boofuzz.Request::new([]).mutations().length(), 0)
  assert_eq(
    @moon_boofuzz.Request::new([@moon_boofuzz.Static(b"A")])
    .mutations()
    .length(),
    0,
  )
}

///|
test "request snapshots caller arrays" {
  let alternatives = [b"B"]
  let fields = [@moon_boofuzz.Choice(b"A", alternatives)]
  let request = @moon_boofuzz.Request::new(fields)
  alternatives.push(b"C")
  fields.push(@moon_boofuzz.Static(b"suffix"))
  assert_eq(request.render(), b"A")
  assert_eq(request.mutations(), [b"B"])
}

///|
test "explicit duplicate and empty alternatives are preserved" {
  let request = @moon_boofuzz.Request::new([
    @moon_boofuzz.Choice(b"A", [b"", b"A", b"A"]),
  ])
  assert_eq(request.mutations(), [b"", b"A", b"A"])
}
