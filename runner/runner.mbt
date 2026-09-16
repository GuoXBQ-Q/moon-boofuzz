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
  NothingReceived
  ConnectionIgnored(String)
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
  config : Json
  variables : Map[String, Bytes]
  check_data_received : Bool
  receive_data_after_fuzz : Bool
  ignore_connection_reset : Bool
  ignore_connection_aborted : Bool
  restart_threshold : Int
  restart_timeout_ms : Int?
  restart_sleep_ms : Int
  sleep_between_ms : Int
  crash_threshold_request : Int
  crash_threshold_element : Int
  end_index : Int?
  udp_server : Bool
  mut request_failures : Int
  element_failures : Map[String, Int]
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
  combinatorial? : Bool = false,
  max_depth? : Int,
  variables? : Map[String, Bytes]? = None,
  check_data_received? : Bool = false,
  receive_data_after_fuzz? : Bool = false,
  ignore_connection_reset? : Bool = false,
  ignore_connection_aborted? : Bool = false,
  restart_threshold? : Int = 0,
  restart_timeout_ms? : Int,
  restart_sleep_ms? : Int = 5000,
  sleep_between_ms? : Int = 0,
  crash_threshold_request? : Int = 12,
  crash_threshold_element? : Int = 3,
  start? : Int = 0,
  end? : Int? = None,
  udp_server? : Bool = false,
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
    streams: paths.map(path => {
      if combinatorial {
        path.combinatorial_cases_with_variables(
          variables,
          limit=2147483647,
          max_depth?,
        )
      } else {
        path.cases_with_variables(variables, start~, limit=2147483647)
      }
    }),
    dial,
    policies: saved,
    receive_limit,
    receive_timeout: receive_timeout_ms,
    limit,
    monitor,
    config: {
      "transport": "custom",
      "max_receive": receive_limit,
      "receive_timeout_ms": receive_timeout_ms,
      "policies": policy_config(saved),
      "case_limit": limit,
    },
    index: 0,
    executed: 0,
    state: Running,
    variables: variables.unwrap_or(Map([])),
    check_data_received,
    receive_data_after_fuzz,
    ignore_connection_reset,
    ignore_connection_aborted,
    restart_threshold,
    restart_timeout_ms,
    restart_sleep_ms,
    sleep_between_ms,
    crash_threshold_request,
    crash_threshold_element,
    request_failures: 0,
    element_failures: Map([]),
    end_index: end,
    udp_server,
  }
}

///|
pub fn Runner::new(
  paths : Array[@core.SessionPath],
  endpoint : @transport.Endpoint,
  udp? : Bool = false,
  udp_server? : Bool = false,
  udp_broadcast? : Bool = false,
  policies? : Map[String, ReadPolicy] = Map([]),
  limit? : Int = 10000,
  monitor? : Monitor = Monitor::new(),
  combinatorial? : Bool = false,
  max_depth? : Int,
  variables? : Map[String, Bytes]? = None,
  check_data_received? : Bool = false,
  receive_data_after_fuzz? : Bool = false,
  ignore_connection_reset? : Bool = false,
  ignore_connection_aborted? : Bool = false,
  restart_threshold? : Int = 0,
  restart_timeout_ms? : Int,
  restart_sleep_ms? : Int = 5000,
  sleep_between_ms? : Int = 0,
  crash_threshold_request? : Int = 12,
  crash_threshold_element? : Int = 3,
  start? : Int = 0,
  end? : Int? = None,
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
    if udp_server {
      @transport.Connection::udp_server(endpoint)
    } else if udp_broadcast {
      @transport.Connection::udp_broadcast(endpoint)
    } else if udp {
      @transport.Connection::udp(endpoint)
    } else {
      @transport.Connection::tcp(endpoint)
    }
  }
  let threshold : Int = restart_threshold
  let runner = Runner::with_dialer(
    paths,
    dial,
    policies~,
    limit~,
    monitor~,
    combinatorial~,
    max_depth?,
    variables~,
    check_data_received~,
    receive_data_after_fuzz~,
    ignore_connection_reset~,
    ignore_connection_aborted~,
    restart_threshold=threshold,
    restart_timeout_ms?,
    restart_sleep_ms~,
    sleep_between_ms~,
    crash_threshold_request~,
    crash_threshold_element~,
    start~,
    end~,
    udp_server~,
    receive_limit=endpoint.receive_limit(),
    receive_timeout_ms=endpoint.receive_timeout(),
  )
  let config_map : Map[String, Json] = Map([])
  config_map["transport"] = if udp_server {
    "udp-server"
  } else if udp_broadcast {
    "udp-broadcast"
  } else if udp {
    "udp"
  } else {
    "tcp"
  }
  config_map["endpoint"] = ToJson::to_json(endpoint)
  config_map["policies"] = policy_config(policies)
  config_map["case_limit"] = limit.to_json()
  if combinatorial {
    config_map["combinatorial"] = true
    match max_depth {
      Some(depth) => config_map["max_depth"] = depth.to_json()
      None => ()
    }
  }
  if sleep_between_ms != 0 {
    config_map["sleep_between_ms"] = sleep_between_ms.to_json()
  }
  if crash_threshold_request != 12 {
    config_map["crash_threshold_request"] = crash_threshold_request.to_json()
  }
  if crash_threshold_element != 3 {
    config_map["crash_threshold_element"] = crash_threshold_element.to_json()
  }
  { ..runner, config: Json::object(config_map), }
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
  defer channel.close()
  if self.udp_server {
    // Server-mode fuzzing answers a peer request with the mutated
    // payload: wait for the request datagram first — send before any
    // receive fails like upstream's BoofuzzError
    // (udp_socket_connection.py:114-116). The request bytes are consumed
    // and not recorded as case steps.
    println("MARK udp-server pre-receive")
    let request = channel.receive(self.receive_limit, self.receive_timeout) catch {
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
    ignore(request)
    println("MARK udp-server pre-receive done")
  }
  let received_all : Array[Bytes] = []
  let case_variables : Map[String, Bytes] = Map([])
  for name, value in self.variables {
    case_variables[name] = value
  }
  let pending = Ref(b"")
  let count = names.length()
  for index in 0..<count {
    // Upstream runs the edge callback before transmitting: the callback may
    // write session variables that the node's render then resolves, and its
    // truthy return value replaces the rendered data (session.py:754-794,
    // 518c139).
    let mut replacement : Bytes? = None
    match path.transitions[index] {
      Some(callback) =>
        replacement = callback({
          variables: case_variables,
          received: received_all.copy(),
          request: names[index],
        })
      None => ()
    }
    let request = path.requests()[index]
    let rendered = if index == count - 1 {
      // The fuzzed payload re-renders at send time so variable writes are
      // visible, matching upstream's render-at-send.
      request.render_case(case.parts(), Some(case_variables))
    } else {
      request.render_with(Some(case_variables))
    }
    let bytes = match replacement {
      Some(data) => if data.length() > 0 { data } else { rendered }
      None => rendered
    }
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
    received_all.push(received.val)
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
fn Runner::retry_dial_failure(
  self : Runner,
  path : @core.SessionPath,
  case : @core.MutationCase,
  result : CaseResult,
) -> CaseResult raise @core.ModelError {
  let mut current = result
  let mut attempts = 0
  while attempts < self.restart_threshold &&
        current.failed_step == Some(-1) &&
        (
          current.outcome is ConnectFailed(_) ||
          current.outcome is ConnectTimedOut
        ) {
    attempts += 1
    let recovered : Bool = (self.monitor.recover)(current.snapshot()) catch {
      _ => false
    }
    @transport.sleep_ms(self.restart_sleep_ms)
    if !recovered {
      return current
    }
    let retried = self.finish(self.execute(path, case))
    if retried.failed_step != Some(-1) || !(retried.outcome is ConnectFailed(_)) {
      return retried
    }
    current = retried
  }
  current
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
      // Upstream's _open_connection_keep_trying: a dial-only failure is
      // retried after recovery, honoring the restart threshold
      // (session.py:1475-1514, 518c139).
      let retry_result = self.retry_dial_failure(
        self.paths[self.index],
        case,
        result,
      )
      // Crash thresholds mirror upstream: repeated failures for the same
      // element (3) or request (12) skip remaining candidates instead of
      // hammering a crashed target (session.py:569-632, 518c139).
      let ignored = retry_result.outcome is ConnectionIgnored(_)
      if retry_result.outcome != Passed && !ignored {
        self.request_failures += 1
        let element = retry_result.case.field_path
        let current = self.element_failures.get(element).unwrap_or(0)
        self.element_failures[element] = current + 1
        if current + 1 >= self.crash_threshold_element {
          let stream = self.streams[self.index]
          while stream.next() is Some(next_case) {
            if next_case.field_path != element {
              break
            }
          }
        }
        if self.request_failures >= self.crash_threshold_request {
          let stream = self.streams[self.index]
          while stream.next() is Some(_) {

          }
          self.index += 1
        }
      }
      if self.sleep_between_ms > 0 {
        @transport.sleep_ms(self.sleep_between_ms)
      }
      self.executed += 1
      return Some(retry_result)
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
