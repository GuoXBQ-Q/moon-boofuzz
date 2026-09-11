///|
pub(all) enum Outcome {
  Passed
  ConnectFailed(Int)
  SendFailed(Int)
  ReceiveFailed(Int)
  ConnectTimedOut
  SendTimedOut
  ReceiveTimedOut
  ConfigurationFailed(String)
  DatagramTooLarge
  PeerClosed
  ResponseMismatch
  CallbackFailed(String)
  RecoveryFailed(String)
} derive(Debug, Eq)

///|
pub(all) struct StepResult {
  request_name : String
  sent : Bytes
  received : Bytes
  completed : Bool
} derive(Debug, Eq)

///|
pub(all) struct CaseResult {
  id : String
  case : @core.MutationCase
  path : Array[String]
  steps : Array[StepResult]
  outcome : Outcome
  failed_step : Int?
} derive(Debug)

///|
pub struct Runner {
  paths : Array[@core.SessionPath]
  streams : Array[@core.CaseStream]
  dial : () -> &Channel raise @transport.TransportError
  policies : Map[String, ReadPolicy]
  receive_limit : Int
  receive_timeout : Int
  limit : Int
  monitor : Monitor
  mut index : Int
  mut executed : Int
  mut state : @core.EnumerationState
}

///|
pub fn Runner::with_dialer(
  paths : Array[@core.SessionPath],
  dial : () -> &Channel raise @transport.TransportError,
  policies? : Map[String, ReadPolicy] = Map([]),
  receive_limit? : Int = 65536,
  receive_timeout_ms? : Int = 5000,
  limit? : Int = 10000,
  monitor? : Monitor = Monitor::new(),
) -> Runner raise {
  guard limit >= 0 &&
    receive_limit > 0 &&
    receive_limit <= 1048576 &&
    receive_timeout_ms > 0 else {
    raise Invalid("invalid runner limits")
  }
  let names : Map[String, Bool] = Map([])
  for path in paths {
    for name in path.names() {
      names[name] = true
    }
  }
  let saved : Map[String, ReadPolicy] = Map([])
  for name, policy in policies {
    guard names.contains(name) else {
      raise Invalid("response policy names unknown request: " + name)
    }
    validate_policy(policy, receive_limit)
    saved[name] = policy
  }
  {
    paths: paths.copy(),
    streams: paths.map(path => path.cases(limit=2147483647)),
    dial,
    policies: saved,
    receive_limit,
    receive_timeout: receive_timeout_ms,
    limit,
    monitor,
    index: 0,
    executed: 0,
    state: Running,
  }
}

///|
pub fn Runner::new(
  paths : Array[@core.SessionPath],
  endpoint : @transport.Endpoint,
  udp? : Bool = false,
  policies? : Map[String, ReadPolicy] = Map([]),
  limit? : Int = 10000,
  monitor? : Monitor = Monitor::new(),
) -> Runner raise {
  for _, policy in policies {
    guard !udp || policy == NoResponse || policy == Datagram else {
      raise Invalid("UDP requires NoResponse or Datagram policy")
    }
    guard udp || policy != Datagram else {
      raise Invalid("Datagram policy requires UDP")
    }
  }
  let dial = fn() -> &Channel raise @transport.TransportError {
    if udp {
      @transport.Connection::udp(endpoint)
    } else {
      @transport.Connection::tcp(endpoint)
    }
  }
  Runner::with_dialer(
    paths,
    dial,
    policies~,
    limit~,
    monitor~,
    receive_limit=endpoint.receive_limit(),
    receive_timeout_ms=endpoint.receive_timeout(),
  )
}

///|
fn Runner::execute(
  self : Runner,
  path : @core.SessionPath,
  case : @core.MutationCase,
) -> CaseResult raise @core.ModelError {
  let names = path.names()
  let id = names.to_json().stringify() + "/" + case.id
  let steps : Array[StepResult] = []
  (self.monitor.before)({ id, case, path: names.copy(), }) catch {
    error =>
      return {
        id,
        case,
        path: names,
        steps,
        outcome: CallbackFailed("before: \{Repr(error)}"),
        failed_step: None,
      }
  }
  let channel = (self.dial)() catch {
    error =>
      return {
        id,
        case,
        path: names,
        steps,
        outcome: transport_outcome(error),
        failed_step: Some(-1),
      }
  }
  defer channel.close()
  let messages = path.prefix()
  messages.push(case.payload)
  let pending = Ref(b"")
  for index, bytes in messages {
    let received = Ref(b"")
    let complete = try {
      channel.send(bytes)
      read_response(
        channel,
        self.policies.get(names[index]).unwrap_or(NoResponse),
        pending,
        received,
        self.receive_limit,
        self.receive_timeout,
      )
    } catch {
      error => {
        let count = channel.last_sent_len().max(0).min(bytes.length())
        steps.push({
          request_name: names[index],
          sent: bytes[:count].to_owned(),
          received: received.val,
          completed: false,
        })
        return {
          id,
          case,
          path: names,
          steps,
          outcome: transport_outcome(error),
          failed_step: Some(index),
        }
      }
    }
    let accepted = if complete {
      (self.monitor.check)(names[index], received.val) catch {
        error => {
          steps.push({
            request_name: names[index],
            sent: bytes,
            received: received.val,
            completed: false,
          })
          return {
            id,
            case,
            path: names,
            steps,
            outcome: CallbackFailed("response check: \{Repr(error)}"),
            failed_step: Some(index),
          }
        }
      }
    } else {
      false
    }
    steps.push({
      request_name: names[index],
      sent: bytes,
      received: received.val,
      completed: complete && accepted,
    })
    if !complete {
      return {
        id,
        case,
        path: names,
        steps,
        outcome: PeerClosed,
        failed_step: Some(index),
      }
    }
    if !accepted {
      return {
        id,
        case,
        path: names,
        steps,
        outcome: ResponseMismatch,
        failed_step: Some(index),
      }
    }
  }
  { id, case, path: names, steps, outcome: Passed, failed_step: None, }
}

///|
pub fn Runner::next(self : Runner) -> CaseResult? raise @core.ModelError {
  guard self.state == Running else { return None }
  if self.executed >= self.limit {
    self.state = Limited
    return None
  }
  errdefer {
    self.state = Stopped
  }
  while self.index < self.paths.length() {
    if self.streams[self.index].next() is Some(case) {
      let result = self.finish(self.execute(self.paths[self.index], case))
      self.executed += 1
      return Some(result)
    }
    self.index += 1
  }
  self.state = Exhausted
  None
}

///|
pub fn Runner::stop(self : Runner) -> Unit {
  self.state = Stopped
}

///|
pub fn Runner::state(self : Runner) -> @core.EnumerationState {
  self.state
}

///|
pub fn Runner::executed(self : Runner) -> Int {
  self.executed
}
