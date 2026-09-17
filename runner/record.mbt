///|
fn policy_config(policies : Map[String, ReadPolicy]) -> Json {
  let result : Map[String, Json] = Map([])
  for name, policy in policies {
    result[name] = match policy {
      NoResponse => { "kind": "none" }
      Fixed(n) => { "kind": "fixed", "length": n }
      Until(bytes) =>
        { "kind": "until", "delimiter_hex": @records.hex_encode(bytes) }
      Datagram => { "kind": "datagram" }
    }
  }
  Json::object(result)
}

///|
pub fn Outcome::name(self : Outcome) -> String {
  match self {
    Passed => "passed"
    ConnectFailed(_) => "connect_failed"
    SendFailed(_) => "send_failed"
    ReceiveFailed(_) => "receive_failed"
    ConnectTimedOut => "connect_timeout"
    SendTimedOut => "send_timeout"
    ReceiveTimedOut => "receive_timeout"
    ConfigurationFailed(_) => "configuration_failed"
    DatagramTooLarge => "datagram_too_large"
    PeerClosed => "peer_closed"
    ResponseMismatch => "response_mismatch"
    CallbackFailed(_) => "callback_failed"
    MonitorFailed(_) => "monitor_failed"
    RecoveryFailed(_) => "recovery_failed"
    NothingReceived => "nothing_received"
    ConnectionIgnored(_) => "connection_ignored"
  }
}

///|
pub fn Runner::record(
  self : Runner,
  result : CaseResult,
) -> @records.CaseRecord {
  {
    format_version: 1,
    case_id: result.id,
    generator_version: "moon-boofuzz-v1",
    request_name: result.case.request_name,
    field_path: result.case.field_path,
    mutation_index: result.case.mutation_index,
    ordinal: result.case.ordinal,
    path: result.path.copy(),
    config: try! @json.parse(self.config.stringify()),
    steps: result.steps.map(step => {
      request_name: step.request_name,
      sent: step.sent,
      received: step.received,
      completed: step.completed,
    }),
    outcome: result.outcome.name(),
    detail: "\{Repr(result.outcome)}",
    failed_step: result.failed_step,
  }
}
