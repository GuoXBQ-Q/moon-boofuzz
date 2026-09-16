// SPDX-License-Identifier: GPL-2.0-only
// Local process monitor, the subset of upstream's ProcessMonitorLocal +
// DebuggerThreadSimple (utils/process_monitor_local.py,
// utils/debugger_thread_simple.py, 518c139) that needs no debugger: spawn
// the target, verify liveness before each case, treat any target exit
// during the run as a fault, and recover by stopping and restarting it.

///|
pub struct ProcessMonitor {
  monitor : @runner.Monitor
  process : Ref[Process?]
  synopsis : Ref[String]
  command : String
  start_delay_ms : Int
  stop_delay_ms : Int
}

///|
/// Build a runner Monitor that owns the target process lifecycle.
/// `start_delay_ms`/`stop_delay_ms` pace restarts the way upstream sleeps
/// between stop and start (restart_sleep_time); tune them for targets that
/// bind sockets lazily.
pub fn ProcessMonitor::new(
  command : String,
  start_delay_ms? : Int = 1000,
  stop_delay_ms? : Int = 500,
) -> ProcessMonitor {
  let state : Ref[Process?] = Ref(None)
  let synopsis : Ref[String] = Ref("")
  let command_copy = command
  let start_copy = start_delay_ms
  let stop_copy = stop_delay_ms
  let start : () -> Unit raise = fn() raise {
    let process = Process::spawn(command_copy)
    state.val = Some(process)
    // POSIX spawns survive the process layer even for broken commands
    // (/bin/sh -c exits 127 milliseconds later), so liveness is confirmed
    // after a minimum settle window: a target that dies within it means
    // failed startup, exactly what upstream start-up heartbeats detect.
    @transport.sleep_ms(if start_copy < 100 { 100 } else { start_copy })
    guard process.alive() else {
      synopsis.val = "target exited during startup with code \{process.exit_code}"
      raise ProcessError::SpawnFailure(process.exit_code)
    }
  }
  let stop : () -> Unit raise = fn() raise {
    match state.val {
      Some(process) => {
        if process.alive() {
          process.kill()
        }
        if stop_copy > 0 {
          @transport.sleep_ms(stop_copy)
        }
        ignore(process.wait(timeout_ms=2000))
        state.val = None
      }
      None => ()
    }
  }
  let monitor = @runner.Monitor::new(
    before=fn(_context) raise {
      // A case must never start against a dead target; death between
      // cases is normally caught by `after` of the previous case.
      match state.val {
        Some(process) => {
          let alive = process.alive()
          guard alive else { raise ProcessError::PollFailure(-1) }
        }
        None => start()
      }
    },
    after=fn(_result) raise {
      // Any target exit during the run is a fault, exit code zero included:
      // upstream's post_send reports death regardless of how it happened.
      match state.val {
        Some(process) => {
          let status = process.status()
          if status.exited {
            let text = "target process exited with code \{status.exit_code}"
            synopsis.val = text
            raise ProcessError::PollFailure(status.exit_code)
          }
        }
        None => ()
      }
    },
    fault=fn(_result) { () },
    recover=fn(_result) {
      // Upstream restart_target: stop what is running, then start again;
      // a failed respawn stops the run with RecoveryFailed.
      try {
        stop()
        start()
        true
      } catch {
        _ => false
      }
    },
  )
  { monitor, process: state, synopsis, command, start_delay_ms, stop_delay_ms, }
}
