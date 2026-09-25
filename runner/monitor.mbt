///|
pub(all) struct CaseContext {
  id : String
  case : @core.MutationCase
  path : Array[String]
} derive(Debug)

///|
pub extend CaseContext with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Raised by a monitor's `after` callback to report a passively detected
/// target failure, like upstream's `post_send()` returning False
/// (sessions/session.py:507-548, 518c139). The runner records the case as
/// the counted failure `MonitorFailed` and runs fault/recover for it;
/// every other `after` exception stays a non-counted `CallbackFailed`.
pub(all) suberror MonitorSignal {
  TargetFailed(reason~ : String)
} derive(Debug)

///|
pub extend MonitorSignal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub struct Monitor {
  before : (CaseContext) -> Unit raise
  after : (CaseResult) -> Unit raise
  fault : (CaseResult) -> Unit raise
  recover : (CaseResult) -> Bool raise
  check : (String, Bytes) -> Bool raise
}

///|
pub fn Monitor::new(
  before? : (CaseContext) -> Unit raise = fn(_) { () },
  after? : (CaseResult) -> Unit raise = fn(_) { () },
  fault? : (CaseResult) -> Unit raise = fn(_) { () },
  recover? : (CaseResult) -> Bool raise = fn(_) { true },
  check? : (String, Bytes) -> Bool raise = fn(_, _) { true },
) -> Monitor {
  { before, after, fault, recover, check, }
}

///|
fn transport_outcome(error : @transport.TransportError) -> Outcome {
  match error {
    InvalidConfiguration(message) => ConfigurationFailed(message)
    ConnectFailure(code) => ConnectFailed(code)
    SendFailure(code) => SendFailed(code)
    ReceiveFailure(code) => ReceiveFailed(code)
    Timeout(Connect) => ConnectTimedOut
    Timeout(Send) => SendTimedOut
    Timeout(Receive) => ReceiveTimedOut
    DatagramTooLarge => DatagramTooLarge
  }
}

///|
fn CaseResult::snapshot(self : CaseResult) -> CaseResult {
  { ..self, path: self.path.copy(), steps: self.steps.copy(), }
}

///|
/// Upstream counts a case as failed only on a monitor log_fail or a raised
/// BoofuzzFailure; ignored connection issues, receive timeouts, clean
/// closes and callback errors are logged without failing the case
/// (session.py:781-903, monitors/callback_monitor.py, 518c139).
fn is_failure(outcome : Outcome) -> Bool {
  match outcome {
    Passed
    | ConnectionIgnored(_)
    | CallbackFailed(_)
    | ReceiveTimedOut
    | PeerClosed => false
    ConnectFailed(_)
    | ConnectTimedOut
    | SendFailed(_)
    | SendTimedOut
    | ReceiveFailed(_)
    | ResponseMismatch
    | ConfigurationFailed(_)
    | DatagramTooLarge
    | MonitorFailed(_)
    | RecoveryFailed(_)
    | NothingReceived => true
  }
}

///|
fn Runner::finish(self : Runner, result : CaseResult) -> CaseResult {
  let mut final_result = result
  (self.monitor.after)(result.snapshot()) catch {
    // A monitor-detected failure counts exactly like upstream's
    // post_send False -> log_fail: it fails the case and drives the
    // fault/recover path below.
    MonitorSignal::TargetFailed(reason~) =>
      final_result = { ..result, outcome: MonitorFailed(reason), }
    error =>
      final_result = {
        ..result,
        outcome: CallbackFailed(
          "after: \{Repr(error)}; prior: \{Repr(result.outcome)}",
        ),
      }
  }
  if is_failure(final_result.outcome) {
    (self.monitor.fault)(final_result.snapshot()) catch {
      // Fault callback exceptions never un-classify an already counted
      // failure; upstream restart handling runs regardless of logging
      // errors (the message is dropped, the outcome is kept).
      _ => ()
    }
    let recovered = (self.monitor.recover)(final_result.snapshot()) catch {
      error => {
        self.state = Stopped
        return {
          ..final_result,
          outcome: RecoveryFailed(
            "\{Repr(error)}; prior: \{Repr(final_result.outcome)}",
          ),
        }
      }
    }
    if !recovered {
      self.state = Stopped
      final_result = {
        ..final_result,
        outcome: RecoveryFailed(
          "recovery returned false; prior: \{Repr(final_result.outcome)}",
        ),
      }
    }
  }
  final_result
}

///|
/// Chain two monitors: both before/after/fault callbacks run in order,
/// `check` requires both to accept, and `recover` requires both to succeed.
/// Used to pair the process monitor with user callbacks.
pub fn Monitor::combine(first : Monitor, second : Monitor) -> Monitor {
  Monitor::new(
    before=fn(context) raise {
      (first.before)(context)
      (second.before)(context)
    },
    after=fn(result) raise {
      (first.after)(result)
      (second.after)(result)
    },
    fault=fn(result) raise {
      (first.fault)(result)
      (second.fault)(result)
    },
    recover=fn(result) {
      let ok_first = (first.recover)(result) catch { _ => false }
      let ok_second = (second.recover)(result) catch { _ => false }
      ok_first && ok_second
    },
    check=fn(name, bytes) {
      let ok_first = (first.check)(name, bytes) catch { _ => false }
      let ok_second = (second.check)(name, bytes) catch { _ => false }
      ok_first && ok_second
    },
  )
}
