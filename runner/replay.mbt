///|
pub(all) struct ReplayResult {
  case_id : String
  steps : Array[StepResult]
  outcome : Outcome
  failed_step : Int?
} derive(Debug)

///|
fn replay_sequence(
  record : @records.CaseRecord,
  config : ExecutionConfig,
  dial : () -> &Channel raise @transport.TransportError,
) -> ReplayResult raise {
  record.validate()
  let saved = record.steps.copy()
  let steps : Array[StepResult] = []
  let channel = dial() catch {
    error =>
      return {
        case_id: record.case_id,
        steps,
        outcome: transport_outcome(error),
        failed_step: Some(-1),
      }
  }
  defer channel.close()
  let pending = Ref(b"")
  for i, original in saved {
    let received = Ref(b"")
    let complete = try {
      channel.send(original.sent)
      read_response(
        channel,
        config.policies.get(original.request_name).unwrap_or(NoResponse),
        pending,
        received,
        config.endpoint.receive_limit(),
        config.endpoint.receive_timeout(),
      )
    } catch {
      error => {
        let sent = channel.last_sent_len().max(0).min(original.sent.length())
        steps.push({
          request_name: original.request_name,
          sent: original.sent[:sent].to_owned(),
          received: received.val,
          completed: false,
        })
        return {
          case_id: record.case_id,
          steps,
          outcome: transport_outcome(error),
          failed_step: Some(i),
        }
      }
    }
    steps.push({
      request_name: original.request_name,
      sent: original.sent,
      received: received.val,
      completed: complete,
    })
    if !complete {
      return {
        case_id: record.case_id,
        steps,
        outcome: PeerClosed,
        failed_step: Some(i),
      }
    }
  }
  { case_id: record.case_id, steps, outcome: Passed, failed_step: None, }
}

///|
/// Replay actual recorded sequences. No protocol compiler or mutation generator runs.
pub fn replay(
  record : @records.CaseRecord,
  override_target? : (String, Int),
) -> ReplayResult raise {
  record.validate()
  let original = ExecutionConfig::parse(record.config)
  let endpoint = match override_target {
    Some((host, port)) => original.endpoint.retarget(host, port)
    None => original.endpoint
  }
  let config = { ..original, endpoint, }
  replay_sequence(record, config, fn() -> &Channel raise @transport.TransportError {
    if config.udp {
      @transport.Connection::udp(endpoint)
    } else {
      @transport.Connection::tcp(endpoint)
    }
  })
}
