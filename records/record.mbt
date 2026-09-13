///|
pub(all) struct RecordedStep {
  request_name : String
  sent : Bytes
  received : Bytes
  completed : Bool
} derive(Debug, Eq)

///|
pub(all) struct CaseRecord {
  format_version : Int
  case_id : String
  generator_version : String
  request_name : String
  field_path : String
  mutation_index : Int
  ordinal : Int
  path : Array[String]
  config : Json
  steps : Array[RecordedStep]
  outcome : String
  detail : String
  failed_step : Int?
} derive(Debug, Eq)

///|
priv struct WireStep {
  request_name : String
  sent_hex : String
  received_hex : String
  completed : Bool
} derive(ToJson, @json.FromJson)

///|
priv struct WireRecord {
  format_version : Int
  case_id : String
  generator_version : String
  request_name : String
  field_path : String
  mutation_index : Int
  ordinal : Int
  path : Array[String]
  config : Json
  steps : Array[WireStep]
  outcome : String
  detail : String
  failed_step : Int?
} derive(ToJson, @json.FromJson)

///|
pub fn require_keys(
  value : Json,
  allowed : Array[String],
) -> Unit raise RecordError {
  guard value is Object(fields) else { raise Invalid("expected JSON object") }
  for key, _ in fields {
    guard allowed.contains(key) else {
      raise Invalid("unknown JSON property: " + key)
    }
  }
}

///|
pub fn CaseRecord::validate(self : CaseRecord) -> Unit raise RecordError {
  guard self.format_version == 1 else {
    raise UnsupportedVersion(self.format_version)
  }
  guard !self.case_id.is_empty() &&
    !self.generator_version.is_empty() &&
    !self.request_name.is_empty() &&
    !self.field_path.is_empty() else {
    raise Invalid("missing case identity")
  }
  guard self.mutation_index >= 0 &&
    self.ordinal >= 0 &&
    self.path.last() == Some(self.request_name) else {
    raise Invalid("invalid case index or request path")
  }
  guard self.steps.length() <= self.path.length() else {
    raise Invalid("too many recorded steps")
  }
  for i, step in self.steps {
    guard step.request_name == self.path[i] else {
      raise Invalid("recorded step/path mismatch")
    }
    guard step.completed || i == self.steps.length() - 1 else {
      raise Invalid("execution continued after failed step")
    }
  }
  if self.failed_step is Some(index) {
    guard index >= -1 && index < self.steps.length() else {
      raise Invalid("invalid failure step")
    }
    guard index != -1 || self.steps.is_empty() else {
      raise Invalid("connect failure has sent steps")
    }
  }
  guard [
    "passed", "connect_failed", "send_failed", "receive_failed", "connect_timeout",
    "send_timeout", "receive_timeout", "configuration_failed", "datagram_too_large",
    "peer_closed", "response_mismatch", "callback_failed", "recovery_failed", "nothing_received",
    "connection_ignored",
  ].contains(self.outcome) else {
    raise Invalid("unknown outcome")
  }
  if self.outcome == "passed" {
    guard self.failed_step is None &&
      self.steps.length() == self.path.length() &&
      self.steps.all(step => step.completed) else {
      raise Invalid("incomplete successful record")
    }
  }
  guard self.config is Object(_) else {
    raise Invalid("execution config must be an object")
  }
}

///|
pub fn CaseRecord::encode(self : CaseRecord) -> String raise RecordError {
  self.validate()
  let wire : WireRecord = {
    format_version: self.format_version,
    case_id: self.case_id,
    generator_version: self.generator_version,
    request_name: self.request_name,
    field_path: self.field_path,
    mutation_index: self.mutation_index,
    ordinal: self.ordinal,
    path: self.path,
    config: self.config,
    steps: self.steps.map(step => {
      request_name: step.request_name,
      sent_hex: hex_encode(step.sent),
      received_hex: hex_encode(step.received),
      completed: step.completed,
    }),
    outcome: self.outcome,
    detail: self.detail,
    failed_step: self.failed_step,
  }
  ToJson::to_json(wire).stringify()
}

///|
pub fn CaseRecord::decode(text : String) -> CaseRecord raise RecordError {
  let json = @json.parse(text) catch {
    error => raise Invalid("invalid JSON: \{Repr(error)}")
  }
  if json is { "format_version": value, .. } {
    let version : Int = @json.from_json(value) catch {
      _ => raise Invalid("format_version must be an integer")
    }
    if version != 1 {
      raise UnsupportedVersion(version)
    }
  }
  require_keys(json, [
    "format_version", "case_id", "generator_version", "request_name", "field_path",
    "mutation_index", "ordinal", "path", "config", "steps", "outcome", "detail",
    "failed_step",
  ])
  if json is { "steps": Array(steps), .. } {
    for step in steps {
      require_keys(step, [
        "request_name", "sent_hex", "received_hex", "completed",
      ])
    }
  }
  let wire : WireRecord = @json.from_json(json) catch {
    error => raise Invalid("invalid record: \{Repr(error)}")
  }
  let record : CaseRecord = {
    format_version: wire.format_version,
    case_id: wire.case_id,
    generator_version: wire.generator_version,
    request_name: wire.request_name,
    field_path: wire.field_path,
    mutation_index: wire.mutation_index,
    ordinal: wire.ordinal,
    path: wire.path,
    config: wire.config,
    steps: wire.steps.map(step => {
      request_name: step.request_name,
      sent: hex_decode(step.sent_hex),
      received: hex_decode(step.received_hex),
      completed: step.completed,
    }),
    outcome: wire.outcome,
    detail: wire.detail,
    failed_step: wire.failed_step,
  }
  record.validate()
  record
}
