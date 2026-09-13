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
pub struct ExecutionConfig {
  endpoint : @transport.Endpoint
  udp : Bool
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
}

///|
pub fn ExecutionConfig::parse(value : Json) -> ExecutionConfig raise {
  @records.require_keys(value, [
    "transport", "endpoint", "policies", "case_limit", "combinatorial", "max_depth",
    "variables", "check_data_received", "receive_data_after_fuzz", "ignore_connection_reset",
    "ignore_connection_aborted", "restart_threshold", "restart_timeout_ms", "restart_sleep_ms",
  ])
  guard value is { "transport": String(kind), "endpoint": endpoint_json, .. } else {
    raise Invalid("execution config requires transport and endpoint")
  }
  guard kind == "tcp" || kind == "udp" else {
    raise Invalid("unsupported recorded transport: " + kind)
  }
  @records.require_keys(endpoint_json, [
    "host", "port", "connect_timeout_ms", "send_timeout_ms", "receive_timeout_ms",
    "max_receive",
  ])
  let wire : WireEndpoint = @json.from_json(endpoint_json)
  let endpoint = @transport.Endpoint::new(
    wire.host,
    wire.port,
    connect_timeout_ms=wire.connect_timeout_ms.unwrap_or(5000),
    send_timeout_ms=wire.send_timeout_ms.unwrap_or(5000),
    receive_timeout_ms=wire.receive_timeout_ms.unwrap_or(5000),
    max_receive=wire.max_receive.unwrap_or(65536),
  )
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
  {
    endpoint,
    udp: kind == "udp",
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
pub fn ExecutionConfig::runner(
  self : ExecutionConfig,
  paths : Array[@core.SessionPath],
  monitor? : Monitor = Monitor::new(),
  limit? : Int,
  combinatorial? : Bool,
  max_depth? : Int,
) -> Runner raise {
  let use_combinatorial = combinatorial.unwrap_or(self.combinatorial)
  let restart_timeout_ms = self.restart_timeout_ms
  let max_depth = match max_depth {
    Some(depth) => Some(depth)
    None => self.max_depth
  }
  Runner::new(
    paths,
    self.endpoint,
    udp=self.udp,
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
  )
}
