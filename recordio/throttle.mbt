// SPDX-License-Identifier: GPL-2.0-only
// JSONL-side keep-only-n throttle, the record-level equivalent of upstream
// fuzz_logger_db.FuzzLoggerDb's queue with num_log_cases
// (fuzz_logger_db.py:206-225): the first case always persists, passing
// cases accumulate in memory, and a failed case — or the final close —
// flushes the last N buffered cases. N = 0 means write everything.

///|
pub struct ThrottledWriter {
  writer : Writer
  buffer : Array[@records.CaseRecord]
  keep : Int
  mut current_ordinal : Int
  mut fail_detected : Bool
  mut first_case : Bool
}

///|
pub fn ThrottledWriter::new(writer : Writer, keep~ : Int) -> ThrottledWriter {
  {
    writer,
    buffer: [],
    keep,
    current_ordinal: 0,
    fail_detected: false,
    first_case: true,
  }
}

///|
fn ThrottledWriter::flush(self : ThrottledWriter, force~ : Bool) -> Unit raise {
  if self.buffer.length() == 0 {
    return
  }
  let mut force = force
  if self.keep > 0 {
    // Keep only the last keep cases, comparing case indexes exactly like
    // fuzz_logger_db.py:209-212.
    while self.buffer.length() > 0 &&
          self.current_ordinal - self.buffer[0].ordinal >= self.keep {
      ignore(self.buffer.remove(0))
    }
  } else {
    force = true
  }
  if force || self.fail_detected || self.first_case {
    for record in self.buffer {
      self.writer.append(record)
    }
    self.buffer.clear()
    self.first_case = false
    self.fail_detected = false
  }
}

///|
/// Buffer one executed case; a failed case flushes the retained window
/// immediately, mirroring close_test_case after log_fail.
pub fn ThrottledWriter::append(
  self : ThrottledWriter,
  record : @records.CaseRecord,
) -> Unit raise {
  self.buffer.push(record)
  self.current_ordinal = record.ordinal
  if record.outcome != "passed" {
    self.fail_detected = true
  }
  self.flush(force=false)
}

///|
/// Final forced flush (upstream close_test): whatever the queue still holds
/// survives the keep-only-n trim.
pub fn ThrottledWriter::close_test(self : ThrottledWriter) -> Unit raise {
  self.flush(force=true)
}
