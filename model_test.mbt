///|
test "named nested blocks compile a stable snapshot with qualified paths" {
  let fields = [
    @moon_boofuzz.Leaf("value", @moon_boofuzz.Field::simple(b"A", [])),
  ]
  let root = @moon_boofuzz.Block::new("request", [
    Nested(@moon_boofuzz.Block::new("left", fields)),
    Nested(
      @moon_boofuzz.Block::new("right", [
        Leaf("value", @moon_boofuzz.Field::simple(b"\x00\xff", [])),
      ]),
    ),
  ])
  fields.clear()
  let request = @moon_boofuzz.CompiledRequest::compile(root)
  assert_eq(request.name(), "request")
  assert_eq(request.render(), b"A\x00\xff")
  assert_eq(request.render_path("request.right.value"), b"\x00\xff")
  assert_eq(request.parent_path("request.right.value"), Some("request.right"))
  assert_eq(request.parent_path("request"), None)
  assert_eq(request.paths(), [
    "request", "request.left", "request.left.value", "request.right", "request.right.value",
  ])
  assert_true(
    try {
      ignore(request.render_path("value"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "compile rejects duplicate names invalid names and byte limit excess" {
  let field = @moon_boofuzz.Field::simple(b"AB", [])
  let duplicate = @moon_boofuzz.Block::new("r", [
    Leaf("x", field),
    Leaf("x", field),
  ])
  assert_true(
    try {
      ignore(@moon_boofuzz.CompiledRequest::compile(duplicate))
      false
    } catch {
      _ => true
    },
  )
  let invalid = @moon_boofuzz.Block::new("r", [Leaf("x.y", field)])
  assert_true(
    try {
      ignore(@moon_boofuzz.CompiledRequest::compile(invalid))
      false
    } catch {
      _ => true
    },
  )
  let root = @moon_boofuzz.Block::new("r", [Leaf("x", field)])
  assert_true(
    try {
      ignore(@moon_boofuzz.CompiledRequest::compile(root, max_bytes=1))
      false
    } catch {
      @moon_boofuzz.ModelError::Limit(_) => true
      _ => false
    },
  )
}

///|
test "legacy request conversion retains defaults" {
  let old = @moon_boofuzz.Request::new([
    Static(b"A"),
    Choice(b"B", [b"C", b"C"]),
  ])
  let compiled = @moon_boofuzz.CompiledRequest::from_request("r", old)
  assert_eq(compiled.render(), old.render())
  assert_eq(compiled.render_path("r.field1"), b"B")
}
