// SPDX-License-Identifier: GPL-2.0-only
// Guards --version against release drift: CLI_VERSION must equal the
// module `version` in moon.mod (moon test runs with the module root as
// working directory).

///|
test "cli version matches moon.mod" {
  let text = @utf8.decode(@recordio.read_bytes("moon.mod"))
  let found : String? = {
    let mut result : String? = None
    for raw in text.split("\n") {
      let line = raw.to_owned()
      if line.has_prefix("version = \"") {
        let rest = line["version = \"".length():].to_owned()
        match rest.find("\"") {
          Some(end) => {
            result = Some(rest[:end].to_owned())
            break
          }
          None => ()
        }
      }
    }
    result
  }
  assert_true(found is Some(_))
  assert_eq(CLI_VERSION, found.unwrap())
}
