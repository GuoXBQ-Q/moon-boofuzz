// SPDX-License-Identifier: GPL-2.0-only
// Opt-in, loopback-only fault-injection routes for fuzzing exercises.
// These endpoints signal command-injection-like inputs or abort at a
// configured length. They never execute commands or corrupt memory.

///|
extern "c" fn lab_abort() -> Unit = "abort"

///|
fn lab_command_marker(input : String) -> Bool {
  let lower = input.to_lower()
  lower.contains(";") ||
  lower.contains("|") ||
  lower.contains("$(") ||
  lower.contains("%3b") ||
  lower.contains("%7c")
}

///|
fn lab_rce_response(hit : Bool) -> Response {
  {
    status: 200,
    content_type: "text/plain",
    body: if hit {
      b"LAB_RCE_HIT\n"
    } else {
      b"LAB_RCE_MISS\n"
    },
  }
}

///|
fn lab_bof_response() -> Response {
  { status: 200, content_type: "text/plain", body: b"LAB_BOF_SAFE\n", }
}

///|
/// Called only when --lab-mode on was explicitly supplied. The two RCE
/// probes return markers; the two BOF probes terminate the process after
/// crossing a length threshold, without performing any out-of-bounds write.
fn ParsedRequest::lab_route(self : ParsedRequest) -> Response? {
  guard self.verb == "GET" else { return None }
  match self.target {
    "/lab/health" =>
      Some({ status: 200, content_type: "text/plain", body: b"LAB_READY\n", })
    "/lab/rce/header" =>
      Some(
        lab_rce_response(
          lab_command_marker(self.header("x-lab-command").unwrap_or("")),
        ),
      )
    "/lab/bof/header" => {
      let length = self.header("x-lab-data").unwrap_or("").length()
      if length > 64 {
        lab_abort()
      }
      Some(lab_bof_response())
    }
    target if target.has_prefix("/lab/rce/path/") => {
      let suffix = target["/lab/rce/path/".length():].to_owned()
      Some(lab_rce_response(lab_command_marker(suffix)))
    }
    target if target.has_prefix("/lab/bof/path/") => {
      let suffix = target["/lab/bof/path/".length():].to_owned()
      if suffix.length() > 128 {
        lab_abort()
      }
      Some(lab_bof_response())
    }
    _ => None
  }
}
