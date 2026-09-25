// SPDX-License-Identifier: GPL-2.0-only
// Native child-process control, the execution substrate for the process
// monitor (upstream pairs utils/process_monitor_local.py with
// utils/debugger_thread_simple.py at 518c139).

///|
pub suberror ProcessError {
  SpawnFailure(Int)
  PollFailure(Int)
  KillFailure(Int)
} derive(Debug)

///|
pub extend ProcessError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub struct Process {
  handle : Proc
  mut exited : Bool
  mut exit_code : Int
}

///|
pub struct ProcessStatus {
  exited : Bool
  exit_code : Int
  pid : Int
} derive(Debug, Eq)

///|
pub extend ProcessStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProcessStatus with Eq::{not_equal, equal}

///|
/// Whether the host is Windows; command strings differ between
/// `cmd /c ...` (full command line to CreateProcessW) and `/bin/sh -c ...`.
pub fn is_windows() -> Bool {
  proc_is_windows() == 1
}

///|
/// Spawn the command asynchronously. Windows takes a full command line;
/// POSIX runs the text through /bin/sh -c.
pub fn Process::spawn(command : String) -> Process raise ProcessError {
  let handle = proc_new()
  let bytes = @utf8.encode(command)
  guard proc_spawn(handle, bytes, bytes.length()) == 0 else {
    raise SpawnFailure(proc_error(handle))
  }
  { handle, exited: false, exit_code: 0, }
}

///|
fn Process::raise_error(self : Process, code : Int) -> ProcessError {
  let slot = proc_error(self.handle)
  match code {
    -1 => PollFailure(slot)
    _ => KillFailure(slot)
  }
}

///|
/// Poll without blocking: exited plus its latched exit code, or running.
/// Once exit is observed the latched result is returned without polling,
/// matching upstream's exit_status staying stable after reaping.
pub fn Process::status(self : Process) -> ProcessStatus raise ProcessError {
  if !self.exited {
    let code = proc_poll(self.handle)
    if code == 0 {
      self.exited = true
      self.exit_code = proc_exit_code(self.handle)
    } else if code == -1 {
      raise self.raise_error(code)
    }
  }
  {
    exited: self.exited,
    exit_code: self.exit_code,
    pid: proc_pid(self.handle),
  }
}

///|
pub fn Process::alive(self : Process) -> Bool raise ProcessError {
  !self.status().exited
}

///|
pub fn Process::pid(self : Process) -> Int {
  proc_pid(self.handle)
}

///|
/// Latched exit code from the most recent poll; meaningful once exited.
pub fn Process::exit_code(self : Process) -> Int {
  self.exit_code
}

///|
/// Terminate the process; the exit code becomes available afterwards.
pub fn Process::kill(self : Process) -> Unit raise ProcessError {
  guard proc_kill(self.handle) == 0 else {
    raise KillFailure(proc_error(self.handle))
  }
}

///|
/// Poll until exit or timeout; None on timeout. Exit code -1 covers
/// signals on POSIX (128+sig) and is reported verbatim otherwise.
pub fn Process::wait(
  self : Process,
  timeout_ms? : Int = 5000,
) -> Int? raise ProcessError {
  let deadline = @transport.monotonic_ms() + timeout_ms.to_int64()
  while @transport.monotonic_ms() < deadline {
    let code = proc_poll(self.handle)
    if code == 0 {
      self.exited = true
      self.exit_code = proc_exit_code(self.handle)
      return Some(self.exit_code)
    }
    if code == -1 {
      raise self.raise_error(code)
    }
    @transport.sleep_ms(10)
  }
  None
}
