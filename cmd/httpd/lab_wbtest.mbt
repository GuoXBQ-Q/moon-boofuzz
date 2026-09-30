// SPDX-License-Identifier: GPL-2.0-only
// Safe-side tests for the opt-in lab routes. Abort cases run out of process.

///|
test "lab endpoints are disabled by default" {
  let config = parse_args([])
  assert_true(!config.lab_mode)
  assert_eq(sample_request(target="/lab/health").route().status, 404)
  assert_eq(sample_request(target="/lab/rce/header").route().status, 404)
}

///|
test "lab mode flag accepts only on or off" {
  assert_true(parse_args(["--lab-mode", "on"]).lab_mode)
  assert_true(!parse_args(["--lab-mode", "off"]).lab_mode)
  assert_true(
    try {
      ignore(parse_args(["--lab-mode", "yes"]))
      false
    } catch {
      HttpdArg(_) => true
    },
  )
}

///|
test "lab RCE probes return a marker without executing input" {
  let path = sample_request(target="/lab/rce/path/item;id")
  assert_eq(path.lab_route().unwrap().body, b"LAB_RCE_HIT\n")
  let encoded = sample_request(target="/lab/rce/path/item%3Bid")
  assert_eq(encoded.lab_route().unwrap().body, b"LAB_RCE_HIT\n")
  let ordinary = sample_request(target="/lab/rce/path/item")
  assert_eq(ordinary.lab_route().unwrap().body, b"LAB_RCE_MISS\n")
  let header = ParsedRequest::{
    ..sample_request(target="/lab/rce/header"),
    headers: [("x-lab-command", "safe|whoami")],
  }
  assert_eq(header.lab_route().unwrap().body, b"LAB_RCE_HIT\n")
}

///|
test "lab BOF probes remain healthy below their thresholds" {
  let header = ParsedRequest::{
    ..sample_request(target="/lab/bof/header"),
    headers: [("x-lab-data", "A".repeat(64))],
  }
  assert_eq(header.lab_route().unwrap().body, b"LAB_BOF_SAFE\n")
  let path = sample_request(target="/lab/bof/path/" + "A".repeat(128))
  assert_eq(path.lab_route().unwrap().body, b"LAB_BOF_SAFE\n")
}
