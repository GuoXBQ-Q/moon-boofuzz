///|
priv struct WireEndpoint {
  host : String
  port : Int
  connect_timeout_ms : Int?
  send_timeout_ms : Int?
  receive_timeout_ms : Int?
  max_receive : Int?
} derive(@json.FromJson)

///|
pub(all) struct ExecutionConfig {
  endpoint : @transport.Endpoint
  udp : Bool
  udp_server : Bool
  udp_broadcast : Bool
  policies : Map[String, ReadPolicy]
  limit : Int
  combinatorial : Bool
  max_depth : Int?
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
  target_command : String?
  target_start_delay_ms : Int
  target_stop_delay_ms : Int
  file_path : String?
}

///|
pub fn ExecutionConfig::parse(value : Json) -> ExecutionConfig raise {
  @records.require_keys(value, [
    "transport", "endpoint", "policies", "case_limit", "combinatorial", "max_depth",
    "variables", "check_data_received", "receive_data_after_fuzz", "sleep_between_ms",
    "crash_threshold_request", "crash_threshold_element", "ignore_connection_reset",
    "target_command", "target_start_delay_ms", "target_stop_delay_ms", "path", "ignore_connection_aborted",
    "restart_threshold", "restart_timeout_ms", "restart_sleep_ms", "udp_server",
    "udp_broadcast",
  ])
  guard value is { "transport": String(kind), .. } else {
    raise Invalid("execution config requires transport and endpoint")
  }
  guard kind == "tcp" || kind == "udp" || kind == "file" else {
    raise Invalid("unsupported recorded transport: " + kind)
  }
  let file_path : String? = if kind == "file" {
    // File transport writes one numbered file per message; only the
    // NoResponse policy is meaningful.
    let path : String = match value {
      Object(fields) =>
        match fields.get("path") {
          Some(item) => @json.from_json(item)
          None => raise Invalid("file transport requires path")
        }
      _ => raise Invalid("file transport requires path")
    }
    guard !path.is_empty() else { raise Invalid("file path must not be empty") }
    Some(path)
  } else {
    None
  }
  let endpoint = if kind == "file" {
    // Placeholder; the file dialer never dials it.
    @transport.Endpoint::new("file", 1)
  } else {
    guard value is { "endpoint": endpoint_json, .. } else {
      raise Invalid("execution config requires transport and endpoint")
    }
    @records.require_keys(endpoint_json, [
      "host", "port", "connect_timeout_ms", "send_timeout_ms", "receive_timeout_ms",
      "max_receive",
    ])
    let wire : WireEndpoint = @json.from_json(endpoint_json)
    @transport.Endpoint::new(
      wire.host,
      wire.port,
      connect_timeout_ms=wire.connect_timeout_ms.unwrap_or(5000),
      send_timeout_ms=wire.send_timeout_ms.unwrap_or(5000),
      receive_timeout_ms=wire.receive_timeout_ms.unwrap_or(5000),
      max_receive=wire.max_receive.unwrap_or(65536),
    )
  }
  let limit : Int = if value is { "case_limit": limit, .. } {
    @json.from_json(limit)
  } else {
    10000
  }
  guard limit >= 0 else { raise Invalid("negative case limit") }
  let policies : Map[String, ReadPolicy] = Map([])
  if value is { "policies": policy_json, .. } {
    guard policy_json is Object(map) else {
      raise Invalid("policies must be an object")
    }
    for name, policy in map {
      guard policy is { "kind": String(policy_kind), .. } else {
        raise Invalid("missing read policy kind")
      }
      let parsed : ReadPolicy = match policy_kind {
        "none" => {
          @records.require_keys(policy, ["kind"])
          NoResponse
        }
        "datagram" => {
          @records.require_keys(policy, ["kind"])
          Datagram
        }
        "fixed" => {
          @records.require_keys(policy, ["kind", "length"])
          guard policy is { "length": n, .. } else {
            raise Invalid("missing fixed length")
          }
          Fixed(@json.from_json(n))
        }
        "until" => {
          @records.require_keys(policy, ["kind", "delimiter_hex"])
          guard policy is { "delimiter_hex": String(hex), .. } else {
            raise Invalid("missing delimiter hex")
          }
          Until(@records.hex_decode(hex))
        }
        _ => raise Invalid("unsupported read policy: " + policy_kind)
      }
      validate_policy(parsed, endpoint.receive_limit())
      guard kind != "udp" || parsed == Datagram || parsed == NoResponse else {
        raise Invalid("UDP requires datagram read policy")
      }
      guard kind != "tcp" || parsed != Datagram else {
        raise Invalid("TCP cannot use datagram policy")
      }
      guard kind != "file" || parsed == NoResponse else {
        raise Invalid("file transport requires none read policies")
      }
      policies[name] = parsed
    }
  }
  let combinatorial = boolean_json(value, "combinatorial")
  let max_depth : Int? = if value is { "max_depth": depth, .. } {
    let parsed : Int = @json.from_json(depth)
    guard parsed >= 1 else { raise Invalid("max_depth must be at least 1") }
    Some(parsed)
  } else {
    None
  }
  let variables : Map[String, Bytes] = Map([])
  if value is { "variables": vars_json, .. } {
    guard vars_json is Object(fields) else {
      raise Invalid("variables must be an object")
    }
    for name, hex_value in fields {
      let text : String = @json.from_json(hex_value)
      variables[name] = @records.hex_decode(text)
    }
  }
  // Server/broadcast modes are UDP-only and mutually exclusive
  // (udp_socket_connection.py:36-45).
  let raw_server = boolean_json(value, "udp_server")
  let raw_broadcast = boolean_json(value, "udp_broadcast")
  guard kind == "udp" || (!raw_server && !raw_broadcast) else {
    raise Invalid("udp_server/udp_broadcast require the udp transport")
  }
  guard !raw_server || !raw_broadcast else {
    raise Invalid("udp_server and udp_broadcast are mutually exclusive")
  }
  {
    endpoint,
    udp: kind == "udp",
    udp_server: raw_server,
    udp_broadcast: raw_broadcast,
    policies,
    limit,
    combinatorial,
    max_depth,
    variables,
    check_data_received: boolean_json(value, "check_data_received"),
    receive_data_after_fuzz: boolean_json(value, "receive_data_after_fuzz"),
    ignore_connection_reset: boolean_json(value, "ignore_connection_reset"),
    ignore_connection_aborted: boolean_json(value, "ignore_connection_aborted"),
    restart_threshold: int_flag(value, "restart_threshold"),
    restart_timeout_ms: optional_positive(value, "restart_timeout_ms"),
    restart_sleep_ms: json_int(value, "restart_sleep_ms", 5000),
    sleep_between_ms: json_int(value, "sleep_between_ms", 0),
    crash_threshold_request: json_int(value, "crash_threshold_request", 12),
    crash_threshold_element: json_int(value, "crash_threshold_element", 3),
    target_command: optional_text(value, "target_command"),
    target_start_delay_ms: json_int(value, "target_start_delay_ms", 1000),
    target_stop_delay_ms: json_int(value, "target_stop_delay_ms", 500),
    file_path,
  }
}

///|
fn optional_text(value : Json, name : String) -> String? raise {
  match value {
    Object(fields) =>
      match fields.get(name) {
        Some(item) => {
          let parsed : String = @json.from_json(item)
          guard !parsed.is_empty() else {
            raise Invalid(name + " must not be empty")
          }
          Some(parsed)
        }
        None => None
      }
    _ => None
  }
}

///|
fn json_int(value : Json, name : String, default : Int) -> Int raise {
  match value {
    Object(fields) =>
      match fields.get(name) {
        Some(item) => {
          let parsed : Int = @json.from_json(item)
          parsed
        }
        None => default
      }
    _ => default
  }
}

///|
fn boolean_json(value : Json, name : String) -> Bool raise {
  match value {
    Object(fields) =>
      match fields.get(name) {
        Some(flag) => {
          let parsed : Bool = @json.from_json(flag)
          parsed
        }
        None => false
      }
    _ => false
  }
}

///|
fn int_flag(value : Json, name : String) -> Int raise {
  match value {
    Object(fields) =>
      match fields.get(name) {
        Some(item) => {
          let parsed : Int = @json.from_json(item)
          guard parsed >= 0 else { raise Invalid("negative " + name) }
          parsed
        }
        None => 0
      }
    _ => 0
  }
}

///|
fn optional_positive(value : Json, name : String) -> Int? raise {
  match value {
    Object(fields) =>
      match fields.get(name) {
        Some(item) => {
          let parsed : Int = @json.from_json(item)
          guard parsed > 0 else { raise Invalid(name + " must be positive") }
          Some(parsed)
        }
        None => None
      }
    _ => None
  }
}

///|
/// Directory prefix for file transports; None for tcp/udp.
pub fn ExecutionConfig::file_path(self : ExecutionConfig) -> String? {
  self.file_path
}

///|
pub fn ExecutionConfig::runner(
  self : ExecutionConfig,
  paths : Array[@core.SessionPath],
  monitor? : Monitor = Monitor::new(),
  limit? : Int,
  combinatorial? : Bool,
  max_depth? : Int,
  start? : Int = 0,
  end? : Int? = None,
  sleep_between? : Int = 0,
  crash_request? : Int = 12,
  crash_element? : Int = 3,
) -> Runner raise {
  let use_combinatorial = combinatorial.unwrap_or(self.combinatorial)
  let restart_timeout_ms = self.restart_timeout_ms
  let max_depth = match max_depth {
    Some(depth) => Some(depth)
    None => self.max_depth
  }
  let sleep_ms = if sleep_between != 0 {
    sleep_between
  } else {
    self.sleep_between_ms
  }
  let crash_req = if crash_request != 12 {
    crash_request
  } else {
    self.crash_threshold_request
  }
  let crash_elem = if crash_element != 3 {
    crash_element
  } else {
    self.crash_threshold_element
  }
  Runner::new(
    paths,
    self.endpoint,
    udp=self.udp,
    udp_server=self.udp_server,
    udp_broadcast=self.udp_broadcast,
    policies=self.policies,
    limit=limit.unwrap_or(self.limit),
    monitor~,
    combinatorial=use_combinatorial,
    max_depth?,
    variables=Some(self.variables),
    check_data_received=self.check_data_received,
    receive_data_after_fuzz=self.receive_data_after_fuzz,
    ignore_connection_reset=self.ignore_connection_reset,
    ignore_connection_aborted=self.ignore_connection_aborted,
    restart_threshold=self.restart_threshold,
    restart_timeout_ms?,
    restart_sleep_ms=self.restart_sleep_ms,
    sleep_between_ms=sleep_ms,
    crash_threshold_request=crash_req,
    crash_threshold_element=crash_elem,
    start~,
    end~,
  )
}
