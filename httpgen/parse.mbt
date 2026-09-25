// SPDX-License-Identifier: GPL-2.0-only
// Parsing of raw HTTP request messages into fuzzer segments. Tolerates
// CRLF or bare-LF line endings; the head terminator and body are kept
// verbatim so a converted definition reproduces the original bytes.

///|
pub(all) suberror HttpGenError {
  Invalid(String)
} derive(Debug)

///|
pub extend HttpGenError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub(all) struct HttpHeader {
  name : String
  /// Whitespace found between the colon and the value (usually " ").
  gap : String
  value : String
} derive(Debug)

///|
pub extend HttpHeader with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub(all) struct HttpMessage {
  verb : String
  uri : String
  version : String
  headers : Array[HttpHeader]
  body : String
  /// True when a head terminator was present, even for an empty body.
  has_body : Bool
  /// True when the unterminated head ends with a line ending.
  final_eol : Bool
  /// Line ending used by the head: "\r\n" or "\n".
  eol : String
  /// The head terminator bytes ("\r\n\r\n" or "\n\n") when present.
  terminator : String?
} derive(Debug)

///|
pub extend HttpMessage with @moonbitlang/core/debug.Debug::{to_repr}

///|
const HTTPGEN_LIMIT : Int = 65536

///|
/// Parse a raw HTTP request. Only requests are supported: fuzzing HTTP
/// responses would require the (unported) TCP server transport mode.
pub fn HttpMessage::parse(source : String) -> HttpMessage raise HttpGenError {
  guard source.length() <= HTTPGEN_LIMIT else {
    raise Invalid("HTTP message exceeds the 64 KiB input limit")
  }
  // Locate the earliest head terminator: CRLFCRLF or bare-LF LFLF.
  let mut head_end = -1
  let mut skip = 0
  for i in 0..<(source.length() - 1) {
    if i + 3 < source.length() &&
      source[i] == '\r' &&
      source[i + 1] == '\n' &&
      source[i + 2] == '\r' &&
      source[i + 3] == '\n' {
      head_end = i
      skip = 4
      break
    }
    if source[i] == '\n' && source[i + 1] == '\n' {
      head_end = i
      skip = 2
      break
    }
  }
  let mut body = ""
  let mut has_body = false
  let mut terminator : String? = None
  let head = if head_end >= 0 {
    terminator = Some(source[head_end:head_end + skip].to_owned())
    has_body = true
    body = source[head_end + skip:].to_owned()
    source[:head_end].to_owned()
  } else {
    source
  }
  let eol = if head.contains("\r") { "\r\n" } else { "\n" }
  let raw_lines = head.split("\n").collect()
  // A trailing newline leaves one empty final element; it is the head's
  // final line ending, not an extra header.
  let mut line_count = raw_lines.length()
  let mut final_eol = false
  if line_count > 0 && raw_lines[line_count - 1].to_owned() == "" {
    final_eol = true
    line_count -= 1
  }
  guard line_count > 0 else { raise Invalid("request line is empty") }
  let request_line = strip_cr(raw_lines[0].to_owned())
  let parts = request_line.split(" ").collect()
  guard parts.length() == 3 else {
    raise Invalid(
      "request line must be METHOD SP URI SP HTTP-VERSION with single spaces",
    )
  }
  let verb = parts[0].to_owned()
  let uri = parts[1].to_owned()
  let version = parts[2].to_owned()
  guard !verb.is_empty() && !uri.is_empty() && !version.is_empty() else {
    raise Invalid("request line has an empty token")
  }
  let headers : Array[HttpHeader] = []
  for i in 1..<line_count {
    headers.push(split_header(strip_cr(raw_lines[i].to_owned())))
  }
  { verb, uri, version, headers, body, has_body, final_eol, eol, terminator, }
}

///|
fn strip_cr(line : String) -> String {
  if line.length() > 0 && line[line.length() - 1] == '\r' {
    line[:line.length() - 1].to_owned()
  } else {
    line
  }
}

///|
fn split_header(line : String) -> HttpHeader raise HttpGenError {
  let colon = match line.find(":") {
    Some(index) => index
    None => raise Invalid("header line is missing a colon: " + line)
  }
  let name = strip_trailing_ows(line[:colon].to_owned())
  guard !name.is_empty() else { raise Invalid("header name is empty") }
  guard name[0] != ' ' && name[0] != '\t' else {
    raise Invalid("header name starts with whitespace: " + line)
  }
  let rest = line[colon + 1:]
  let mut gap_end = 0
  while gap_end < rest.length() &&
        (rest[gap_end] == ' ' || rest[gap_end] == '\t') {
    gap_end += 1
  }
  {
    name,
    gap: rest[:gap_end].to_owned(),
    value: strip_trailing_ows(rest[gap_end:].to_owned()),
  }
}

///|
fn strip_trailing_ows(text : String) -> String {
  let mut end = text.length()
  while end > 0 && (text[end - 1] == ' ' || text[end - 1] == '\t') {
    end -= 1
  }
  text[:end].to_owned()
}
