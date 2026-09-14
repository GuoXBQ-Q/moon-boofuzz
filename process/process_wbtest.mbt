// Process control unit tests. Commands are platform-specific: Windows runs
// full command lines through CreateProcessW, POSIX text through /bin/sh -c.

///|
fn exit3_command() -> String {
  if is_windows() {
    "cmd /c exit 3"
  } else {
    "exit 3"
  }
}

///|
fn slow_command() -> String {
  if is_windows() {
    "cmd /c ping -n 30 127.0.0.1 > nul"
  } else {
    "sleep 30"
  }
}

///|
test "spawn reports exit code and pid" {
  let process = Process::spawn(exit3_command())
  assert_true(process.pid() > 0)
  let code = process.wait(timeout_ms=10000)
  assert_eq(code, Some(3))
  let status = process.status()
  assert_true(status.exited)
  assert_eq(status.exit_code, 3)
}

///|
test "kill terminates a running process" {
  let process = Process::spawn(slow_command())
  assert_true(process.alive())
  process.kill()
  let code = process.wait(timeout_ms=10000)
  // POSIX reaps with signal semantics (128+SIGTERM); Windows uses the
  // TerminateProcess code 1. Either way it exited.
  assert_true(code is Some(_))
  assert_false(process.alive())
}

///|
test "wait returns None on timeout" {
  let process = Process::spawn(slow_command())
  assert_eq(process.wait(timeout_ms=50), None)
  assert_true(process.alive())
  process.kill()
  ignore(process.wait(timeout_ms=10000))
}
