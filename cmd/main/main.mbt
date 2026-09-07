///|
fn main {
  let request = @boofuzz.Request::new([
    @boofuzz.Static(b"PING "),
    @boofuzz.Choice(b"ok", [b"", b"long-value"]),
    @boofuzz.Static(b"\r\n"),
  ])
  println("moon-boofuzz: offline mutation example")
  println("default: \{Repr(request.render())}")
  for index, payload in request.mutations() {
    println("case \{index}: \{Repr(payload)}")
  }
}
