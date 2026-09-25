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
  /// A monitor passively detected a target failure after the case ran
  /// (upstream: monitor post_send returning False -> log_fail). Unlike
  /// CallbackFailed this is a counted failure and drives fault/recover.
  MonitorFailed(String)
  RecoveryFailed(String)
  NothingReceived
  ConnectionIgnored(String)
} derive(Debug, Eq)

///|
pub extend Outcome with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Outcome with Eq::{not_equal, equal}

///|
pub(all) struct StepResult {
  request_name : String
  sent : Bytes
  received : Bytes
  completed : Bool
} derive(Debug, Eq)

///|
pub extend StepResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend StepResult with Eq::{not_equal, equal}

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
pub extend CaseResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub struct Runner {
  paths : Array[@core.SessionPath]
  /// Case streams are built lazily so a global start offset can carry
  /// across paths exactly like ProtocolDefinition::generate.
  streams : Array[@core.CaseStream?]
  dial : () -> &Channel raise @transport.TransportError
  policies : Map[String, ReadPolicy]
  receive_limit : Int
  receive_timeout : Int
  limit : Int
  monitor : Monitor
  config : Json
  variables : Map[String, Bytes]
  stream_variables : Map[String, Bytes]?
  combinatorial : Bool
  max_depth : Int?
  check_data_received : Bool
  receive_data_after_fuzz : Bool
  ignore_connection_reset : Bool
  ignore_connection_aborted : Bool
  ignore_connection_issues_when_sending_fuzz_data : Bool
  /// Failed-dial give-up count; None (the default) retries indefinitely
  /// like upstream's restart_threshold=None (session.py:1475-1514).
  restart_threshold : Int?
  restart_timeout_ms : Int?
  restart_sleep_ms : Int
  sleep_between_ms : Int
  crash_threshold_request : Int
  crash_threshold_element : Int
  end_index : Int?
  udp_server : Bool
  /// Failures per path, keyed like upstream's crashing_primitives[fuzz_node].
  path_failures : Array[Int]
  element_failures : Map[String, Int]
  /// Lookahead buffer so element drains stop at the next element's first
  /// case instead of discarding it.
  mut pending : @core.MutationCase?
  /// Global start offset not yet consumed by a lazy stream.
  mut skip : Int
  /// Global case ordinal (skipped + executed + drained), the coordinate of
  /// --start/--end, as upstream's total_mutant_index (session.py:1073-1091).
  mut position : Int
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
  ignore_connection_issues_when_sending_fuzz_data? : Bool = true,
  restart_threshold? : Int? = None,
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
    streams: Array::make(paths.length(), None),
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
    stream_variables: variables,
    combinatorial,
    max_depth,
    check_data_received,
    receive_data_after_fuzz,
    ignore_connection_reset,
    ignore_connection_aborted,
    ignore_connection_issues_when_sending_fuzz_data,
    restart_threshold,
    restart_timeout_ms,
    restart_sleep_ms,
    sleep_between_ms,
    crash_threshold_request,
    crash_threshold_element,
    path_failures: Array::make(paths.length(), 0),
    element_failures: Map([]),
    pending: None,
    skip: start,
    position: start,
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
  ignore_connection_issues_when_sending_fuzz_data? : Bool = true,
  restart_threshold? : Int? = None,
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
    ignore_connection_issues_when_sending_fuzz_data~,
    restart_threshold~,
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
  if self.udp_server {
    // Server-mode fuzzing answers a peer request with the mutated
    // payload: wait for the request datagram first — send before any
    // receive fails like upstream's BoofuzzError
    // (udp_socket_connection.py:114-116). The request bytes are consumed
    // and not recorded as case steps.
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
    let policy = self.policies.get(names[index]).unwrap_or(NoResponse)
    let fuzz_node = index == count - 1
    // Send stage. Connection resets/aborts are governed by the ignore
    // flags: the fuzzed node by ignore_connection_issues_when_sending_
    // fuzz_data, prefix nodes by ignore_connection_reset/aborted
    // (session.py:838-874, 518c139). An ignored issue records the case as
    // ConnectionIgnored, which is not a counted failure.
    let send_error : @transport.TransportError? = try {
      channel.send(bytes)
      None
    } catch {
      error => Some(error)
    }
    if send_error is Some(error) {
      let sent = channel.last_sent_len().max(0).min(bytes.length())
      steps.push({
        request_name: names[index],
        sent: bytes[:sent].to_owned(),
        received: b"",
        completed: false,
      })
      let ignored = match error {
        @transport.TransportError::SendFailure(code) =>
          match @transport.classify_socket_failure(code) {
            Reset =>
              if fuzz_node {
                self.ignore_connection_issues_when_sending_fuzz_data
              } else {
                self.ignore_connection_reset
              }
            Aborted =>
              if fuzz_node {
                self.ignore_connection_issues_when_sending_fuzz_data
              } else {
                self.ignore_connection_aborted
              }
            _ => false
          }
        _ => false
      }
      return {
        id,
        case,
        path: names,
        steps,
        outcome: if ignored {
          ConnectionIgnored("send reset/aborted at step \{index}")
        } else {
          transport_outcome(error)
        },
        failed_step: Some(index),
      }
    }
    // Receive stage. A receive timeout maps to empty data, a clean close to
    // an empty read, and a reset/abort is ignored unless
    // check_data_received upgrades it — none of them is a counted failure,
    // matching upstream's transmit functions (session.py:815-903, 518c139).
    let read : ReadOutcome = try {
      if policy == NoResponse {
        if fuzz_node && self.receive_data_after_fuzz {
          // Upstream attempts a recv after the fuzzed node only when
          // receive_data_after_fuzz is set (session.py:883).
          match channel.receive(self.receive_limit, self.receive_timeout) {
            Data(bytes) => {
              received.val = bytes
              Complete
            }
            Closed => Closed
          }
        } else {
          Complete
        }
      } else if read_response(
          channel,
          policy,
          pending,
          received,
          self.receive_limit,
          self.receive_timeout,
        ) {
        Complete
      } else {
        Closed
      }
    } catch {
      error =>
        match error {
          @transport.TransportError::Timeout(Receive) => TimedOut
          @transport.TransportError::ReceiveFailure(code) =>
            match @transport.classify_socket_failure(code) {
              Reset | Aborted => ResetAborted(code)
              _ => Failed(error)
            }
          _ => Failed(error)
        }
    }
    let step_result = fn(outcome : Outcome) -> CaseResult {
      { id, case, path: names, steps, outcome, failed_step: Some(index), }
    }
    let read_outcome = fn(default : Outcome) -> Outcome {
      // check_data_received upgrades an empty read to a failure, like
      // upstream's "Nothing received from target." (session.py:822-828).
      if self.check_data_received && received.val.is_empty() {
        NothingReceived
      } else {
        default
      }
    }
    match read {
      Complete => ()
      TimedOut => {
        steps.push({
          request_name: names[index],
          sent: bytes,
          received: received.val,
          completed: false,
        })
        return step_result(read_outcome(ReceiveTimedOut))
      }
      Closed => {
        steps.push({
          request_name: names[index],
          sent: bytes,
          received: received.val,
          completed: false,
        })
        return step_result(read_outcome(PeerClosed))
      }
      ResetAborted(code) => {
        steps.push({
          request_name: names[index],
          sent: bytes,
          received: received.val,
          completed: false,
        })
        return step_result(
          read_outcome(
            ConnectionIgnored("receive reset (\{code}) at step \{index}"),
          ),
        )
      }
      Failed(error) => {
        steps.push({
          request_name: names[index],
          sent: bytes,
          received: received.val,
          completed: false,
        })
        return step_result(transport_outcome(error))
      }
    }
    let accepted = (self.monitor.check)(names[index], received.val) catch {
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
    steps.push({
      request_name: names[index],
      sent: bytes,
      received: received.val,
      completed: accepted,
    })
    received_all.push(received.val)
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
/// Pull the next case of a path, preferring the lookahead buffer so a case
/// is only ever consumed once across threshold drains.
fn Runner::pull(
  self : Runner,
  index : Int,
) -> @core.MutationCase? raise @core.ModelError {
  match self.pending {
    Some(saved) => {
      self.pending = None
      Some(saved)
    }
    None =>
      match self.streams[index] {
        Some(stream) => stream.next()
        None => None
      }
  }
}

///|
/// Exhaust the remaining candidates of one element, buffering the first
/// case of the next element instead of discarding it; upstream skips only
/// the remaining mutations of the crashing element (session.py:614-627).
fn Runner::drain_element(
  self : Runner,
  index : Int,
  element : String,
) -> Unit raise @core.ModelError {
  while self.pull(index) is Some(next_case) {
    self.position += 1
    if next_case.field_path != element {
      self.pending = Some(next_case)
      return
    }
  }
}

///|
/// Exhaust the current path after its crash threshold; other paths keep
/// fuzzing, matching upstream's per-node exhaustion.
fn Runner::drain_path(
  self : Runner,
  index : Int,
) -> Unit raise @core.ModelError {
  while self.pull(index) is Some(_) {
    self.position += 1
  }
}

///|
/// A dial-only failure: the connection was never established. A UDP
/// server's pre-receive shares failed_step -1 but is a response timeout,
/// not a dial failure.
fn is_dial_failure(result : CaseResult) -> Bool {
  result.failed_step == Some(-1) &&
  (result.outcome is ConnectFailed(_) || result.outcome is ConnectTimedOut)
}

///|
/// Upstream's _open_connection_keep_trying: recover the target and retry
/// the dial. With no threshold (the default) it retries indefinitely. An
/// explicit threshold counts completed *restarts*: upstream checks the
/// counter before restarting and increments it after, so threshold N
/// allows N restarts and N+1 dials (session.py:1486-1508, 518c139). An
/// explicit restart_timeout bounds the whole loop. Giving up ends the run
/// after this recorded case, like upstream re-raising out of the fuzz
/// loop.
fn Runner::recover_and_retry(
  self : Runner,
  path : @core.SessionPath,
  case : @core.MutationCase,
  first : CaseResult,
) -> CaseResult raise @core.ModelError {
  let started = @transport.monotonic_ms()
  let mut current = first
  let mut restarts = 0
  while true {
    // Upstream's falsy check: a threshold of 0 means never give up, so
    // only a positive count ends the loop (session.py:1491).
    if self.restart_threshold is Some(threshold) &&
      threshold > 0 &&
      restarts >= threshold {
      self.state = Stopped
      return current
    }
    if self.restart_timeout_ms is Some(timeout) &&
      @transport.monotonic_ms() - started >= timeout.to_int64() {
      self.state = Stopped
      return current
    }
    let recovered : Bool = (self.monitor.recover)(current.snapshot()) catch {
      _ => false
    }
    if !recovered {
      // A failed restart cannot make the target reachable; upstream ends
      // the run when the restart handler raises.
      self.state = Stopped
      return current
    }
    // Upstream increments unable_to_connect_count after the restart, so
    // the give-up check above compares completed restarts, not dials.
    restarts += 1
    if self.restart_sleep_ms > 0 {
      @transport.sleep_ms(self.restart_sleep_ms)
    }
    let retried = self.execute(path, case)
    if !is_dial_failure(retried) {
      return self.finish(retried)
    }
    current = retried
  }
  current
}

///|
pub fn Runner::next(self : Runner) -> CaseResult? raise @core.ModelError {
  guard self.state == Running else { return None }
  errdefer {
    self.state = Stopped
  }
  while self.index < self.paths.length() {
    // --start/--end are global ordinals across paths: cases below start are
    // pulled but never executed, and the run stops once the next ordinal
    // would reach end (session.py:1073-1091, 518c139).
    if self.end_index is Some(end) && self.position >= end {
      self.state = Limited
      return None
    }
    if self.executed >= self.limit {
      self.state = Limited
      return None
    }
    let stream = match self.streams[self.index] {
      Some(stream) => stream
      None => {
        // A sequential skip beyond a path's raw case count carries into the
        // next path, mirroring ProtocolDefinition::generate.
        if !self.combinatorial {
          let count = self.paths[self.index].target().raw_mutation_count()
          if self.skip.to_int64() >= count {
            self.skip -= count.to_int()
            self.index += 1
            continue
          }
        }
        let start = self.skip
        self.skip = 0
        let path = self.paths[self.index]
        let max_depth = self.max_depth
        let built = if self.combinatorial {
          path.combinatorial_cases_with_variables(
            self.stream_variables,
            start~,
            limit=2147483647,
            max_depth?,
          )
        } else {
          path.cases_with_variables(
            self.stream_variables,
            start~,
            limit=2147483647,
          )
        }
        self.streams[self.index] = Some(built)
        built
      }
    }
    let case = match self.pending {
      Some(saved) => {
        self.pending = None
        saved
      }
      None =>
        match stream.next() {
          Some(case) => case
          None => {
            // A combinatorial stream that exhausts before consuming its
            // start offset leaves the remainder for the next path.
            if self.combinatorial && stream.remaining_skip() > 0 {
              self.skip = stream.remaining_skip()
            }
            self.index += 1
            continue
          }
        }
    }
    self.position += 1
    let raw = self.execute(self.paths[self.index], case)
    // Dial-only failures take the reconnect path and skip the post-case
    // failure machinery: upstream restarts the target inside the connect
    // retry loop instead (_open_connection_keep_trying).
    let result = if is_dial_failure(raw) {
      self.recover_and_retry(self.paths[self.index], case, raw)
    } else {
      self.finish(raw)
    }
    if self.state == Stopped {
      // Give-up (retry threshold/timeout or failed recovery) ends the run
      // after this case, like upstream re-raising out of the fuzz loop.
      self.executed += 1
      return Some(result)
    }
    // Crash thresholds mirror upstream's per-node and per-element counters;
    // only counted failures reach here — dial failures take the reconnect
    // path, and ignored issues/timeouts/closures/callback errors are not
    // failures (session.py:591-627, 518c139).
    if is_failure(result.outcome) {
      self.path_failures[self.index] += 1
      let element = result.case.field_path
      let current = self.element_failures.get(element).unwrap_or(0)
      self.element_failures[element] = current + 1
      if current + 1 >= self.crash_threshold_element {
        self.drain_element(self.index, element)
      }
      if self.path_failures[self.index] >= self.crash_threshold_request {
        self.drain_path(self.index)
      }
    }
    if self.sleep_between_ms > 0 {
      @transport.sleep_ms(self.sleep_between_ms)
    }
    self.executed += 1
    return Some(result)
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
