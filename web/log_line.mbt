// SPDX-License-Identifier: GPL-2.0-only
// Log line rendering, porting helpers.test_step_info html entries and
// format_log_msg (helpers.py:29-102, :359-399) at 518c139: per-type html
// templates, css classes, description-vs-hex message selection, the
// truncation note, and "timestamp + indent" prefixing.

///|
pub(all) struct LogLine {
  css_class : String
  log_line : String
} derive(Debug, Eq)

///|
fn type_css_class(step_type : String) -> String {
  match step_type {
    "test_case" => "log-case"
    "step" => "log-step"
    "info" => "log-info"
    "error" => "log-error"
    "send" => "log-send"
    "receive" => "log-receive"
    "check" => "log-check"
    "fail" => "log-fail"
    "pass" => "log-pass"
    _ => "log-info"
  }
}

///|
fn type_indent(step_type : String) -> Int {
  match step_type {
    "test_case" => 0
    "step" => 1
    "info" | "error" | "send" | "receive" | "check" => 2
    "fail" | "pass" => 3
    _ => 0
  }
}

///|
/// hex_str + repr rendering of payload bytes
/// (helpers.hex_to_hexstr): lowercase hex, then the best-effort text form.
fn bytes_message(data : Bytes) -> String {
  @records.hex_encode(data) + " " + bytes_repr(data)
}

///|
fn bytes_repr(data : Bytes) -> String {
  let builder = StringBuilder()
  builder <+ "b'"
  for byte in data {
    if byte >= b'\x20' && byte < b'\x7f' {
      let ch = byte.to_char()
      builder <+ "\{ch}"
    } else {
      let hex = @records.hex_encode(Bytes::makei(1, _ => byte))
      builder <+ "\\x\{hex}"
    }
  }
  builder <+ "'"
  builder.to_string()
}

///|
fn format_log_line(
  step_type : String,
  description : String,
  data : Bytes,
  truncated? : Bool = false,
  timestamp? : String = "",
) -> LogLine {
  let note = if truncated {
    " (data truncated for database storage)"
  } else {
    ""
  }
  let message = if !description.is_empty() {
    description
  } else if data.length() > 0 {
    bytes_message(data)
  } else {
    ""
  }
  let template = match step_type {
    "send" => "Transmitted \{data.length()} bytes\{note}: \{message}"
    "receive" => "Received\{note}: \{message}"
    "test_case" => "Test Case: \{message}"
    "step" => " Test Step: \{message}"
    "info" => "Info: \{message}"
    "error" => "Error!!!! \{message}"
    "check" => "Check: \{message}"
    "fail" => "Check Failed: \{message}"
    "pass" => "Check OK: \{message}"
    _ => message
  }
  let indent = " ".repeat(type_indent(step_type) * 2)
  let line = if timestamp.is_empty() {
    indent + template
  } else {
    timestamp + " " + indent + template
  }
  { css_class: type_css_class(step_type), log_line: line, }
}

///|
/// The log lines of one test case: the case header followed by one entry
/// per step (upstream DataTestCase.html_log_line and _get_log_data).
fn case_log_lines(case : @db.DbCase) -> Array[LogLine] {
  let lines : Array[LogLine] = []
  lines.push(
    format_log_line(
      "test_case",
      "\{case.index}: \{case.name}",
      b"",
      timestamp=case.timestamp,
    ),
  )
  for step in case.steps {
    lines.push(
      format_log_line(
        step.step_type,
        step.description,
        step.data,
        truncated=step.truncated,
        timestamp=step.timestamp,
      ),
    )
  }
  lines
}
