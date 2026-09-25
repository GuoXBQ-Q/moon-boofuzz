// SPDX-License-Identifier: GPL-2.0-only
// Conversion of a parsed HTTP message plus field selections into a
// moon-boofuzz protocol-definition JSON document (schema version 1).
// The children list reproduces the original bytes exactly when every
// field is frozen: structural bytes (spaces, line endings, header name
// prefixes, the head terminator) become static fields. Selected fields
// pick a mutation primitive: string library, integer boundaries, binary
// blob, random data or explicit candidates.

///|
pub(all) enum FieldPrimitive {
  Text
  Integer
  Bytes
  RandomData
  Candidates
} derive(Debug, Eq)

///|
pub extend FieldPrimitive with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FieldPrimitive with Eq::{not_equal, equal}

///|
pub(all) struct FieldSelection {
  id : String
  primitive : FieldPrimitive
  /// Integer primitive: bit width, one of 8/16/32/64.
  width : Int
  /// Integer primitive: "little" or "big".
  endian : String
  /// Bytes primitive: maximum rendered length; random primitive:
  /// maximum data length.
  max_len : Int
  /// Random primitive: number of generated cases.
  max_mutations : Int
  /// Explicit replacement values; empty means automatic mutations.
  candidates : Array[String]
} derive(Debug)

///|
pub extend FieldSelection with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub(all) struct ConvertOptions {
  request_name : String
  host : String
  port : Int
  /// "until" | "none" | "fixed"
  policy_kind : String
  /// Response length for the "fixed" read policy.
  fixed_length : Int
  case_limit : Int
} derive(Debug)

///|
pub extend ConvertOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub(all) struct ConvertResult {
  definition : Json
  definition_text : String
  case_count : Int
  previews : Array[Bytes]
} derive(Debug)

///|
pub extend ConvertResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Candidate methods offered when the method is selected with the
/// candidates primitive but no explicit values. The original method is
/// removed from the list.
fn builtin_methods() -> Array[String] {
  [
    "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE", "CONNECT",
    "PROPFIND",
  ]
}

///|
pub fn to_definition(
  message : HttpMessage,
  selections : Array[FieldSelection],
  options : ConvertOptions,
) -> ConvertResult raise HttpGenError {
  let chosen : Map[String, FieldSelection] = Map([])
  for selection in selections {
    guard message.valid_id(selection.id) else {
      raise Invalid("unknown segment: " + selection.id)
    }
    guard !chosen.contains(selection.id) else {
      raise Invalid("duplicate selection: " + selection.id)
    }
    chosen[selection.id] = {
      ..selection,
      candidates: selection.candidates.filter(c => !c.is_empty()),
    }
  }
  let children : Array[Json] = []
  children.push(field_node("method", message.verb, chosen.get("method")))
  children.push(static_node("sp1", " "))
  children.push(field_node("uri", message.uri, chosen.get("uri")))
  children.push(static_node("sp2", " "))
  children.push(field_node("version", message.version, chosen.get("version")))
  // The request line ends with a line ending whenever anything follows it.
  if message.headers.length() > 0 ||
    message.terminator is Some(_) ||
    message.final_eol {
    children.push(static_node("crlf0", message.eol))
  }
  for i, header in message.headers {
    children.push(static_node("name_\{i}", header.name + ":" + header.gap))
    children.push(field_node("hdr_\{i}", header.value, chosen.get("hdr_\{i}")))
    let is_last_header = i == message.headers.length() - 1
    if message.terminator is Some(_) || !is_last_header || message.final_eol {
      children.push(static_node("crlf\{i + 1}", message.eol))
    }
  }
  match message.terminator {
    Some(terminator) => {
      // The terminator's first line ending was already emitted after the
      // last head line; only the remainder opens the body.
      children.push(static_node("head_end", terminator_remainder(terminator)))
      children.push(field_node("body", message.body, chosen.get("body")))
    }
    None => ()
  }
  let request_name = if options.request_name.is_empty() {
    "request"
  } else {
    options.request_name
  }
  let host = if options.host.is_empty() { "127.0.0.1" } else { options.host }
  guard options.port >= 1 && options.port <= 65535 else {
    raise Invalid("port must be between 1 and 65535")
  }
  guard options.case_limit >= 0 else { raise Invalid("negative case limit") }
  let policy : Json = match options.policy_kind {
    "until" => { "kind": "until", "delimiter_hex": "0d0a0d0a" }
    "none" => { "kind": "none" }
    "fixed" => {
      guard options.fixed_length >= 0 else {
        raise Invalid("negative fixed read length")
      }
      { "kind": "fixed", "length": options.fixed_length }
    }
    other => raise Invalid("unsupported read policy: " + other)
  }
  let policies : Map[String, Json] = Map([])
  policies[request_name] = policy
  let request : Json = { "name": request_name, "children": children }
  let definition : Json = {
    "schema_version": 1,
    "requests": [request],
    "execution": {
      "transport": "tcp",
      "endpoint": {
        "host": host,
        "port": options.port,
        "receive_timeout_ms": 500,
      },
      "policies": Json::object(policies),
      "case_limit": options.case_limit,
    },
  }
  let definition_text = definition.stringify()
  let parsed = @definition.ProtocolDefinition::parse(definition_text) catch {
    error =>
      raise Invalid("generated definition failed validation: \{Repr(error)}")
  }
  let mut total = 0L
  for compiled in parsed.requests() {
    total += compiled.raw_mutation_count()
  }
  guard total <= 2147483647L else {
    raise Invalid("generated definition exceeds the 32-bit case range")
  }
  let previews : Array[Bytes] = []
  ignore(
    parsed.generate(
      case => {
        previews.push(case.case.payload)
        previews.length() < 3
      },
      limit=3,
    ),
  ) catch {
    _ => raise Invalid("generated definition failed to enumerate cases")
  }
  { definition, definition_text, case_count: total.to_int(), previews, }
}

///|
/// Whether the id names a segment of this message (used to validate
/// selections coming back from the web form).
pub fn HttpMessage::valid_id(self : HttpMessage, id : String) -> Bool {
  match id {
    "method" | "uri" | "version" => true
    "body" => self.has_body
    _ => {
      let mut valid = false
      if id.has_prefix("hdr_") {
        for i in 0..<self.headers.length() {
          if id == "hdr_\{i}" {
            valid = true
          }
        }
      }
      valid
    }
  }
}

///|
/// Case-insensitive lookup of the first header value with that name.
pub fn HttpMessage::header(self : HttpMessage, name : String) -> String? {
  let wanted = name.to_lower()
  for header in self.headers {
    if header.name.to_lower() == wanted {
      return Some(header.value)
    }
  }
  None
}

///|
fn static_node(name : String, content : String) -> Json {
  let node : Json = {
    "type": "static",
    "name": name,
    "value_hex": @records.hex_encode(@utf8.encode(content)),
  }
  node
}

///|
/// A frozen segment renders a text field with fuzzable=false; a selected
/// segment renders the node for its chosen primitive.
fn field_node(
  name : String,
  value : String,
  selection : FieldSelection?,
) -> Json raise HttpGenError {
  let primitive = match selection {
    Some(selection) => selection.primitive
    None =>
      return { "type": "text", "name": name, "value": value, "fuzzable": false }
  }
  match primitive {
    Text => auto_text_node(name, value)
    Integer => integer_node(name, value, selection.unwrap())
    Bytes => bytes_node(name, value, selection.unwrap())
    RandomData => random_node(name, value, selection.unwrap())
    Candidates => {
      let candidates = selection.unwrap().candidates
      if candidates.is_empty() {
        // A method without explicit candidates falls back to the built-in
        // HTTP method table; every other segment falls back to the string
        // library, matching the historical auto-mutation behavior.
        if name == "method" {
          candidates_node(
            name,
            value,
            builtin_methods().filter(candidate => candidate != value),
          )
        } else {
          auto_text_node(name, value)
        }
      } else {
        candidates_node(name, value, candidates)
      }
    }
  }
}

///|
fn auto_text_node(name : String, value : String) -> Json {
  let node : Json = {
    "type": "text",
    "name": name,
    "value": value,
    "fuzzable": true,
  }
  node
}

///|
fn candidates_node(
  name : String,
  value : String,
  candidates : Array[String],
) -> Json {
  let encoded : Array[String] = candidates.map(candidate => {
    @records.hex_encode(@utf8.encode(candidate))
  })
  let node : Json = {
    "type": "simple",
    "name": name,
    "value_hex": @records.hex_encode(@utf8.encode(value)),
    "values_hex": encoded,
    "fuzzable": true,
  }
  node
}

///|
fn integer_node(
  name : String,
  value : String,
  selection : FieldSelection,
) -> Json raise HttpGenError {
  guard selection.width == 8 ||
    selection.width == 16 ||
    selection.width == 32 ||
    selection.width == 64 else {
    raise Invalid("integer width must be 8, 16, 32 or 64 bits")
  }
  guard selection.endian == "little" || selection.endian == "big" else {
    raise Invalid("integer endian must be little or big")
  }
  let node : Json = {
    "type": "integer",
    "name": name,
    "value": decimal_or_zero(value),
    "width": selection.width,
    "endian": selection.endian,
    "fuzzable": true,
  }
  node
}

///|
/// The original text as the integer default when it is a decimal number,
/// "0" otherwise; upstream integers render binary, so this only keeps a
/// numeric-looking segment recognizable in normal renders.
fn decimal_or_zero(text : String) -> String {
  if text.is_empty() || text.length() > 20 {
    return "0"
  }
  for ch in text {
    guard ch >= '0' && ch <= '9' else { return "0" }
  }
  text
}

///|
fn bytes_node(
  name : String,
  value : String,
  selection : FieldSelection,
) -> Json raise HttpGenError {
  guard selection.max_len >= 1 else {
    raise Invalid("bytes max_len must be at least 1")
  }
  let node : Json = {
    "type": "bytes",
    "name": name,
    "value_hex": @records.hex_encode(@utf8.encode(value)),
    "max_len": selection.max_len,
    "fuzzable": true,
  }
  node
}

///|
fn random_node(
  name : String,
  value : String,
  selection : FieldSelection,
) -> Json raise HttpGenError {
  guard selection.max_len >= 1 else {
    raise Invalid("random max_length must be at least 1")
  }
  guard selection.max_mutations >= 1 else {
    raise Invalid("random max_mutations must be at least 1")
  }
  let node : Json = {
    "type": "random",
    "name": name,
    "value_hex": @records.hex_encode(@utf8.encode(value)),
    "min_length": 0,
    "max_length": selection.max_len,
    "max_mutations": selection.max_mutations,
    "fuzzable": true,
  }
  node
}

///|
/// The terminator bytes after its first line ending, which was already
/// emitted as the last head line's line ending.
fn terminator_remainder(terminator : String) -> String {
  if terminator.has_prefix("\r\n") {
    terminator[2:].to_owned()
  } else {
    terminator[1:].to_owned()
  }
}
