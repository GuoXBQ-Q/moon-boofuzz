///|
fn request_fixture(
  request : @moon_boofuzz.CompiledRequest,
) -> @moon_boofuzz.Field raise {
  let stream = request.cases()
  let cases : Array[Bytes] = []
  while stream.next() is Some(case) {
    cases.push(case.payload)
  }
  @moon_boofuzz.Field::simple(request.render(), cases)
}
