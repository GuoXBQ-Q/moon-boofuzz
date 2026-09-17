// SPDX-License-Identifier: GPL-2.0-only
// Blackbox tests for the sqlite layer: open/exec roundtrip, the logger's
// upstream queue semantics, reader/failure_map, and 512-byte truncation.

///|
test "Db open/exec/prepare roundtrip" {
  let path = @db.temp_path()
  defer @db.remove_file(path)
  let db = @db.Db::open(path)
  defer db.close()
  db.exec("CREATE TABLE t (a integer, b text)")
  let stmt = db.prepare("INSERT INTO t VALUES(?, ?)")
  stmt.run([@db.VInt(42L), @db.VText("hello")])
  stmt.run([@db.VNull, @db.VBlob(b"\x01\x02\xff")])
  stmt.close()
  let query = db.prepare("SELECT a, b FROM t ORDER BY rowid")
  let rows = query.query([])
  query.close()
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].values[0], @db.VInt(42L))
  assert_eq(rows[0].values[1], @db.VText("hello"))
  assert_eq(rows[1].values[0], @db.VNull)
  assert_eq(rows[1].values[1], @db.VBlob(b"\x01\x02\xff"))
}

///|
fn sample_record(
  ordinal : Int,
  outcome : String,
  sent : Bytes,
  received : Bytes,
) -> @records.CaseRecord {
  let connect_failed = outcome == "connect_failed"
  {
    format_version: 1,
    case_id: "case-\{ordinal}",
    generator_version: "moon-boofuzz-v1",
    request_name: "udp_request",
    field_path: "udp_request",
    mutation_index: ordinal,
    ordinal,
    path: ["udp_request"],
    config: { "kind": "none" },
    steps: if connect_failed {
      []
    } else {
      [
        {
          request_name: "udp_request",
          sent,
          received,
          completed: outcome == "passed",
        },
      ]
    },
    outcome,
    detail: outcome,
    failed_step: if outcome == "passed" {
      None
    } else if connect_failed {
      Some(-1)
    } else {
      Some(0)
    },
  }
}

///|
test "DbLogger persists every case when num_log_cases is 0" {
  let path = @db.temp_path()
  defer @db.remove_file(path)
  let stamps : Array[String] = [
    "2026-01-01T00:00:01", "2026-01-01T00:00:02", "2026-01-01T00:00:03",
  ]
  let mut tick = 0
  let logger = @db.DbLogger::open_with_clock(path, num_log_cases=0, now=fn() {
    let stamp = stamps[tick % stamps.length()]
    tick += 1
    stamp
  })
  defer logger.close()
  for ordinal in 0..<3 {
    logger.log_record(sample_record(ordinal, "passed", b"\xaa", b"\xbb"))
  }
  logger.close_test()
  let reader = @db.DbReader::open(path)
  defer reader.close()
  let count = reader.query("SELECT count(*) FROM cases")
  assert_eq(count[0].values[0], @db.VInt(3L))
  let case0 = reader.get_test_case_data(0)
  assert_eq(case0.name, "udp_request")
  assert_eq(case0.index, 0)
  assert_eq(case0.steps.length(), 4)
  assert_eq(case0.steps[0].step_type, "step")
  assert_eq(case0.steps[1].step_type, "send")
  assert_eq(case0.steps[1].data, b"\xaa")
  assert_eq(case0.steps[2].step_type, "receive")
  assert_eq(case0.steps[2].data, b"\xbb")
  assert_eq(case0.steps[3].step_type, "pass")
  let failures = reader.failure_map()
  assert_eq(failures.length(), 0)
}

///|
test "DbReader failure map and NoSuchCase" {
  let path = @db.temp_path()
  defer @db.remove_file(path)
  let logger = @db.DbLogger::open(path)
  defer logger.close()
  logger.log_record(sample_record(0, "passed", b"\xaa", b"\xbb"))
  logger.log_record(sample_record(1, "receive_failed", b"\xcc", b""))
  logger.log_record(sample_record(2, "connect_failed", b"", b""))
  logger.close_test()
  let reader = @db.DbReader::open(path)
  defer reader.close()
  let failures = reader.failure_map()
  // Upstream failure_map only collects "fail" steps; connection errors log
  // type "error" and stay out of the map (fuzz_logger_db.py:283).
  assert_eq(failures.length(), 1)
  assert_eq(failures.get(1), Some(["receive_failed"]))
  assert_eq(failures.get(2), None)
  // Connection failures log_error, which flushes immediately; other
  // failures log_fail.
  let kinds = reader.query(
    "SELECT DISTINCT type FROM steps WHERE type != 'send' AND type != 'receive' AND type != 'step' ORDER BY type",
  )
  let names = kinds.map(row => row.values[0])
  assert_eq(names, [@db.VText("error"), @db.VText("fail"), @db.VText("pass")])
  try reader.get_test_case_data(9) catch {
    @db.NoSuchCase(9) => ()
    error => fail("expected NoSuchCase, got \{Repr(error)}")
  } noraise {
    _ => fail("expected NoSuchCase")
  }
}

///|
test "keep-only-n passes: first case plus the last window survive" {
  let path = @db.temp_path()
  defer @db.remove_file(path)
  // Upstream fuzz_logger_db.py:206-225 with num_log_cases=2 and three
  // passing cases followed by a failing one: case 0 persists (first case),
  // case 1 is dropped, cases 2 and 3 persist (fail flushes the window).
  let logger = @db.DbLogger::open(path, num_log_cases=2)
  defer logger.close()
  logger.log_record(sample_record(0, "passed", b"\x01", b""))
  logger.log_record(sample_record(1, "passed", b"\x02", b""))
  logger.log_record(sample_record(2, "passed", b"\x03", b""))
  logger.log_record(sample_record(3, "send_failed", b"\x04", b""))
  logger.close_test()
  let reader = @db.DbReader::open(path)
  defer reader.close()
  let indexes = reader
    .query("SELECT number FROM cases ORDER BY number")
    .map(row => row.values[0])
  assert_eq(indexes, [@db.VInt(0L), @db.VInt(2L), @db.VInt(3L)])
}

///|
test "512-byte truncation applies to passing cases only" {
  let path = @db.temp_path()
  defer @db.remove_file(path)
  let big : Bytes = Bytes::make(600, b'\x7f')
  let logger = @db.DbLogger::open(path)
  defer logger.close()
  logger.log_record(sample_record(0, "passed", big, big))
  logger.log_record(sample_record(1, "send_failed", big, b""))
  logger.close_test()
  let reader = @db.DbReader::open(path)
  defer reader.close()
  let passed = reader.get_test_case_data(0)
  let send = passed.steps.filter(step => step.step_type == "send")
  assert_eq(send.length(), 1)
  assert_eq(send[0].data.length(), @db.DATA_TRUNCATE_LENGTH)
  assert_true(send[0].truncated)
  // Upstream's "recv"/"receive" mismatch leaves receive rows untruncated;
  // the quirk is preserved so databases stay byte-comparable.
  let receive = passed.steps.filter(step => step.step_type == "receive")
  assert_eq(receive.length(), 1)
  assert_eq(receive[0].data.length(), 600)
  assert_true(!receive[0].truncated)
  let failed = reader.get_test_case_data(1)
  let failed_send = failed.steps.filter(step => step.step_type == "send")
  assert_eq(failed_send[0].data.length(), 600)
  assert_true(!failed_send[0].truncated)
}

///|
test "reopen keeps appending without recreating the schema" {
  let path = @db.temp_path()
  defer @db.remove_file(path)
  let first = @db.DbLogger::open(path)
  first.log_record(sample_record(0, "passed", b"\x01", b""))
  first.close_test()
  first.close()
  let second = @db.DbLogger::open(path)
  second.log_record(sample_record(1, "passed", b"\x02", b""))
  second.close_test()
  second.close()
  let reader = @db.DbReader::open(path)
  defer reader.close()
  let count = reader.query("SELECT count(*) FROM cases")
  assert_eq(count[0].values[0], @db.VInt(2L))
}
