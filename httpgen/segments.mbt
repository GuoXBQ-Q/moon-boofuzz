// SPDX-License-Identifier: GPL-2.0-only
// Fuzzable segment extraction: stable ids shared by the web form and the
// definition emitter, one segment per request-line token, header value
// and body.

///|
pub(all) struct Segment {
  /// Stable id used in form fields and selections: method, uri, version,
  /// hdr_<index> or body.
  id : String
  label : String
  /// method | uri | version | header | body
  kind : String
  value : String
} derive(Debug)

///|
pub extend Segment with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The fuzzable segments of the message in wire order.
pub fn HttpMessage::segments(self : HttpMessage) -> Array[Segment] {
  let result : Array[Segment] = [
    { id: "method", label: "Method", kind: "method", value: self.verb, },
    { id: "uri", label: "URI", kind: "uri", value: self.uri, },
    { id: "version", label: "Version", kind: "version", value: self.version, },
  ]
  for i, header in self.headers {
    result.push({
      id: "hdr_\{i}",
      label: "Header \{header.name}",
      kind: "header",
      value: header.value,
    })
  }
  if self.has_body {
    result.push({ id: "body", label: "Body", kind: "body", value: self.body, })
  }
  result
}
