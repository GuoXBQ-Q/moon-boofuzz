// ProcessMonitor lifecycle: before starts the target, after flags any exit
// as a fault, recover stops and restarts; a broken command fails recovery.

///|
test "process monitor spawns restarts and reports crashes" {
  let monitor = ProcessMonitor::new(
    slow_command(),
    start_delay_ms=0,
    stop_delay_ms=0,
  )
  let context : @runner.CaseContext = {
    id: "test",
    case: placeholder_case(),
    path: ["r"],
  }
  // First before spawns the target.
  (monitor.monitor.before)(context)
  assert_true(monitor.process.val is Some(_))
  // A passing case: after observes a live target.
  (monitor.monitor.after)(placeholder_result())
  // Kill out-of-band: after must flag the death as a fault.
  let process = monitor.process.val.unwrap()
  process.kill()
  ignore(process.wait(timeout_ms=10000))
  let mut raised = false
  (monitor.monitor.after)(placeholder_result()) catch {
    @runner.MonitorSignal::TargetFailed(reason~) => {
      raised = true
      assert_true(reason.contains("exited"))
    }
    _ => ()
  }
  assert_true(raised)
  assert_true(monitor.synopsis.val.contains("exited"))
  // Recover stops and restarts; before then sees a live target again.
  assert_true((monitor.monitor.recover)(placeholder_result()))
  (monitor.monitor.before)(context)
  assert_true(monitor.process.val.unwrap().alive())
  // Clean up for the GC finalizer.
  monitor.process.val.unwrap().kill()
}

///|
test "process monitor fails recovery on a broken command" {
  let monitor = ProcessMonitor::new(
    "definitely-not-a-real-command-4b1f",
    start_delay_ms=0,
    stop_delay_ms=0,
  )
  // Broken spawn raises from recover? No: recover swallows and returns
  // false so the runner stops with RecoveryFailed.
  assert_false((monitor.monitor.recover)(placeholder_result()))
}

///|
test "process monitor start reports immediate-exit command" {
  let monitor = ProcessMonitor::new(
    exit3_command(),
    start_delay_ms=200,
    stop_delay_ms=0,
  )
  let mut raised = false
  let recovered = (monitor.monitor.recover)(placeholder_result()) catch {
    _ => {
      raised = true
      false
    }
  }
  // The command exits within the start delay window, so recovery reports
  // failure through the alive check (false) or the spawn guard (raise).
  assert_false(recovered && !raised)
}

///|
fn placeholder_case() -> @core.MutationCase {
  {
    id: "v1:r.x:0",
    request_name: "r",
    field_path: "r.x",
    mutation_index: 0,
    ordinal: 0,
    payload: b"",
    extra: [],
  }
}

///|
fn placeholder_result() -> @runner.CaseResult {
  {
    id: "test",
    case: placeholder_case(),
    path: ["r"],
    steps: [],
    outcome: Passed,
    failed_step: None,
  }
}
