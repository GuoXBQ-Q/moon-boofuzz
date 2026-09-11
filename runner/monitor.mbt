///|
pub(all) struct CaseContext {
  id : String
  case : @core.MutationCase
  path : Array[String]
} derive(Debug)

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
fn Runner::finish(self : Runner, result : CaseResult) -> CaseResult {
  let mut final_result = result
  (self.monitor.after)(result.snapshot()) catch {
    error =>
      final_result = {
        ..result,
        outcome: CallbackFailed(
          "after: \{Repr(error)}; prior: \{Repr(result.outcome)}",
        ),
      }
  }
  if final_result.outcome != Passed {
    (self.monitor.fault)(final_result.snapshot()) catch {
      error =>
        final_result = {
          ..final_result,
          outcome: CallbackFailed(
            "fault: \{Repr(error)}; prior: \{Repr(final_result.outcome)}",
          ),
        }
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
