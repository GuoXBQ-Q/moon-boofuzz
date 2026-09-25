// SPDX-License-Identifier: GPL-2.0-only
// Port of upstream fuzz_logger_db.FuzzLoggerDb at 518c139. Schema, the
// write queue with keep-only-n throttle, fail-flush, first-case persistence
// and the 512-byte send/recv truncation follow fuzz_logger_db.py lines
// 39-230 one for one; see docs/DB.md for the mapping table.

///|
/// Upstream `_data_truncate_length` (fuzz_logger_db.py:58).
pub const DATA_TRUNCATE_LENGTH : Int = 512

///|
const CASES_DDL : String = "CREATE TABLE cases (name text, number integer, timestamp TEXT)"

///|
const STEPS_DDL : String = "CREATE TABLE steps (test_case_index integer, type text, description text, data blob, timestamp TEXT, is_truncated BOOLEAN)"

///|
/// One queued write, mirroring the (sql, params) pairs upstream keeps in
/// `_queue` (fuzz_logger_db.py:54): either a `cases` row or a `steps` row
/// with its columns.
pub(all) enum DbLogEntry {
  CasesEntry(String, Int, String)
  StepsEntry(Int, String, String, Bytes, String, Bool)
} derive(Debug, Eq)

///|
pub extend DbLogEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbLogEntry with Eq::{not_equal, equal}

///|
fn DbLogEntry::case_index(self : DbLogEntry) -> Int {
  match self {
    CasesEntry(_, index, _) => index
    StepsEntry(index, _, _, _, _, _) => index
  }
}

///|
pub struct DbLogger {
  db : Db
  cases : Stmt
  steps : Stmt
  queue : Array[DbLogEntry]
  mut current_index : Int
  queue_max_len : Int
  mut fail_detected : Bool
  mut first_case : Bool
  now : () -> String
}

///|
/// Open (creating if absent) a results database with the upstream schema.
/// `num_log_cases` mirrors upstream `num_log_cases` / the CLI's
/// --record-passes: 0 persists every case, N keeps only the last N passing
/// cases (fuzz_logger_db.py:206-225).
pub fn DbLogger::open(
  path : String,
  num_log_cases? : Int = 0,
) -> DbLogger raise DbError {
  DbLogger::open_with_clock(path, num_log_cases~, now=fn() {
    @utf8.decode_lossy(now_iso())
  })
}

///|
/// DbLogger::open with an injectable clock for deterministic tests.
pub fn DbLogger::open_with_clock(
  path : String,
  num_log_cases? : Int = 0,
  now~ : () -> String,
) -> DbLogger raise DbError {
  let db = Db::open(path)
  errdefer db.close()
  if !schema_present(db) {
    // Only a fresh database gets the DDL, matching upstream's
    // "if not db_already_exist" guard (fuzz_logger_db.py:40-50).
    db.exec(CASES_DDL)
    db.exec(STEPS_DDL)
  }
  let cases = db.prepare("INSERT INTO cases VALUES(?, ?, ?)")
  errdefer cases.close()
  let steps = db.prepare("INSERT INTO steps VALUES(?, ?, ?, ?, ?, ?)")
  {
    db,
    cases,
    steps,
    queue: [],
    current_index: 0,
    queue_max_len: num_log_cases,
    fail_detected: false,
    first_case: true,
    now,
  }
}

///|
fn schema_present(db : Db) -> Bool raise DbError {
  let rows = db
    .prepare(
      "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='cases'",
    )
    .query([])
  rows.length() > 0 &&
  (match rows[0].values[0] {
    VInt(count) => count > 0L
    _ => false
  })
}

///|
fn truncate_entry(entry : DbLogEntry) -> DbLogEntry {
  // Upstream _truncate_send_recv (fuzz_logger_db.py:227-230) tests the type
  // against "recv" while log_recv queues "receive", so in practice only
  // send rows shrink (and only while the case has not failed). The quirk
  // is preserved verbatim so databases stay byte-comparable.
  match entry {
    StepsEntry(index, kind, description, data, stamp, _) =>
      if kind == "send" && data.length() > DATA_TRUNCATE_LENGTH {
        StepsEntry(
          index,
          kind,
          description,
          data[0:DATA_TRUNCATE_LENGTH].to_owned(),
          stamp,
          true,
        )
      } else {
        entry
      }
    other => other
  }
}

///|
fn execute_entry(logger : DbLogger, entry : DbLogEntry) -> Unit raise DbError {
  match entry {
    CasesEntry(name, index, stamp) =>
      logger.cases.run([VText(name), VInt(index.to_int64()), VText(stamp)])
    StepsEntry(index, kind, description, data, stamp, truncated) =>
      logger.steps.run([
        VInt(index.to_int64()),
        VText(kind),
        VText(description),
        VBlob(data),
        VText(stamp),
        VInt(if truncated { 1L } else { 0L }),
      ])
  }
}

///|
fn write_log(logger : DbLogger, force? : Bool = false) -> Unit raise DbError {
  if logger.queue.length() == 0 {
    return
  }
  let mut force = force
  if logger.queue_max_len > 0 {
    // Keep only the last num_log_cases cases in the queue
    // (fuzz_logger_db.py:208-212).
    while logger.queue.length() > 0 &&
          logger.current_index - logger.queue[0].case_index() >=
          logger.queue_max_len {
      ignore(logger.queue.remove(0))
    }
  } else {
    force = true
  }
  if force || logger.fail_detected || logger.first_case {
    let truncating = !logger.fail_detected
    logger.db.exec("BEGIN")
    errdefer logger.db.exec("ROLLBACK")
    for entry in logger.queue {
      execute_entry(
        logger,
        if truncating {
          truncate_entry(entry)
        } else {
          entry
        },
      )
    }
    logger.db.exec("COMMIT")
    logger.queue.clear()
    logger.first_case = false
    logger.fail_detected = false
  }
}

///|
/// Persist and release the underlying statements and connection. Pending
/// queue entries are NOT flushed: call close_test first, mirroring the
/// upstream session close sequence.
pub fn DbLogger::close(self : DbLogger) -> Unit {
  self.steps.close()
  self.cases.close()
  self.db.close()
}

///|
/// open_test_case: queue the cases row and adopt the index
/// (fuzz_logger_db.py:89-91).
pub fn DbLogger::open_test_case(
  self : DbLogger,
  name~ : String,
  index~ : Int,
) -> Unit {
  self.queue.push(CasesEntry(name, index, (self.now)()))
  self.current_index = index
}

///|
pub fn DbLogger::open_step(self : DbLogger, description~ : String) -> Unit {
  self.queue.push(
    StepsEntry(
      self.current_index,
      "step",
      description,
      b"",
      (self.now)(),
      false,
    ),
  )
}

///|
pub fn DbLogger::log_check(self : DbLogger, description~ : String) -> Unit {
  self.queue.push(
    StepsEntry(
      self.current_index,
      "check",
      description,
      b"",
      (self.now)(),
      false,
    ),
  )
}

///|
/// log_error marks the case failed and flushes immediately
/// (fuzz_logger_db.py:119-132).
pub fn DbLogger::log_error(
  self : DbLogger,
  description~ : String,
) -> Unit raise {
  self.queue.push(
    StepsEntry(
      self.current_index,
      "error",
      description,
      b"",
      (self.now)(),
      false,
    ),
  )
  self.fail_detected = true
  write_log(self)
}

///|
pub fn DbLogger::log_recv(self : DbLogger, data~ : Bytes) -> Unit {
  self.queue.push(
    StepsEntry(self.current_index, "receive", "", data, (self.now)(), false),
  )
}

///|
pub fn DbLogger::log_send(self : DbLogger, data~ : Bytes) -> Unit {
  self.queue.push(
    StepsEntry(self.current_index, "send", "", data, (self.now)(), false),
  )
}

///|
pub fn DbLogger::log_info(self : DbLogger, description~ : String) -> Unit {
  self.queue.push(
    StepsEntry(
      self.current_index,
      "info",
      description,
      b"",
      (self.now)(),
      false,
    ),
  )
}

///|
pub fn DbLogger::log_fail(self : DbLogger, description~ : String) -> Unit {
  self.queue.push(
    StepsEntry(
      self.current_index,
      "fail",
      description,
      b"",
      (self.now)(),
      false,
    ),
  )
  self.fail_detected = true
}

///|
pub fn DbLogger::log_pass(self : DbLogger, description~ : String) -> Unit {
  self.queue.push(
    StepsEntry(
      self.current_index,
      "pass",
      description,
      b"",
      (self.now)(),
      false,
    ),
  )
}

///|
pub fn DbLogger::close_test_case(self : DbLogger) -> Unit raise {
  write_log(self, force=false)
}

///|
pub fn DbLogger::close_test(self : DbLogger) -> Unit raise {
  write_log(self, force=true)
}

///|
/// Replay one executed-case record into the database using the upstream log
/// sequence: a cases row, a step row plus send/receive rows per recorded
/// step, then the outcome row (pass, or fail/error — connection failures
/// log_error like upstream) — and finally the case close. failed cases keep
/// full payloads; passed cases are subject to keep-only-n and truncation.
pub fn DbLogger::log_record(
  self : DbLogger,
  record : @records.CaseRecord,
) -> Unit raise {
  self.open_test_case(name=record.request_name, index=record.ordinal)
  for step in record.steps {
    self.open_step(description=step.request_name)
    self.log_send(data=step.sent)
    self.log_recv(data=step.received)
  }
  if record.outcome == "passed" {
    self.log_pass(description=record.detail)
  } else {
    match record.failed_step {
      Some(-1) => self.log_error(description=record.detail)
      _ => self.log_fail(description=record.detail)
    }
  }
  self.close_test_case()
}
