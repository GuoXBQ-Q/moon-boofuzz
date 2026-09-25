///|
pub(all) struct RecordIssue {
  line : Int
  message : String
} derive(Debug, Eq)

///|
pub extend RecordIssue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RecordIssue with Eq::{not_equal, equal}

///|
pub(all) struct RecordRead {
  records : Array[CaseRecord]
  error : RecordIssue?
} derive(Debug)

///|
pub extend RecordRead with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Preserve preceding complete records on a malformed or incomplete line.
pub fn parse_jsonl_bytes(bytes : Bytes) -> RecordRead {
  let records : Array[CaseRecord] = []
  let mut start = 0
  for i, byte in bytes {
    if byte == b'\n' {
      let record = try {
        let line = @utf8.decode(bytes[start:i])
        CaseRecord::decode(line)
      } catch {
        error =>
          return {
            records,
            error: Some({
              line: records.length() + 1,
              message: "\{Repr(error)}",
            }),
          }
      }
      records.push(record)
      start = i + 1
    }
  }
  if start < bytes.length() {
    {
      records,
      error: Some({
        line: records.length() + 1,
        message: "incomplete final JSONL line",
      }),
    }
  } else {
    { records, error: None, }
  }
}

///|
pub fn parse_jsonl(text : String) -> RecordRead {
  parse_jsonl_bytes(@utf8.encode(text))
}
