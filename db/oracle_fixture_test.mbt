// SPDX-License-Identifier: GPL-2.0-only
// Differential fixture: a results database created by upstream boofuzz
// 0.4.2 at 518c139 (fixtures/db/oracle-run.db, from a real CI run — the
// schema was written by fuzz_logger_db.py:46-50; the run itself never
// opened a case). The ported reader must accept it unchanged, and the
// exact INSERT statements upstream queues must run on this layer.

///|
test "read the schema written by upstream boofuzz" {
  let reader = @db.DbReader::open("fixtures/db/oracle-run.db")
  defer reader.close()
  let tables = reader.query(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
  )
  assert_eq(tables.map(row => row.values[0]), [
    @db.VText("cases"),
    @db.VText("steps"),
  ])
  let columns = reader.query("SELECT name FROM pragma_table_info('steps')")
  assert_eq(columns.map(row => row.values[0]), [
    @db.VText("test_case_index"),
    @db.VText("type"),
    @db.VText("description"),
    @db.VText("data"),
    @db.VText("timestamp"),
    @db.VText("is_truncated"),
  ])
  assert_eq(
    reader.query("SELECT count(*) FROM cases")[0].values[0],
    @db.VInt(0L),
  )
  try reader.get_test_case_data(0) catch {
    @db.NoSuchCase(0) => ()
    error => fail("expected NoSuchCase, got \{Repr(error)}")
  } noraise {
    _ => fail("expected NoSuchCase")
  }
  assert_eq(reader.failure_map().length(), 0)
}

///|
test "accept the exact SQL statements upstream queues" {
  let path = @db.temp_path()
  defer @db.remove_file(path)
  let db = @db.Db::open(path)
  defer db.close()
  // fuzz_logger_db.py:46-50 and :90-102 verbatim, including the trailing
  // ";\n" upstream appends to every queued statement.
  db.exec("CREATE TABLE cases (name text, number integer, timestamp TEXT)")
  db.exec(
    "CREATE TABLE steps (test_case_index integer, type text, description text, data blob, timestamp TEXT, is_truncated BOOLEAN)",
  )
  let case_insert = db.prepare("INSERT INTO cases VALUES(?, ?, ?);\n")
  case_insert.run([
    @db.VText("udp_request"),
    @db.VInt(7L),
    @db.VText("2026-09-16T09:00:00.123456"),
  ])
  case_insert.close()
  let step_insert = db.prepare("INSERT INTO steps VALUES(?, ?, ?, ?, ?, ?);\n")
  step_insert.run([
    @db.VInt(7L),
    @db.VText("send"),
    @db.VText(""),
    @db.VBlob(b"\xde\xad\xbe\xef"),
    @db.VText("2026-09-16T09:00:00.234567"),
    @db.VInt(0L),
  ])
  step_insert.close()
  let reader = @db.DbReader::open(path)
  defer reader.close()
  let case_data = reader.get_test_case_data(7)
  assert_eq(case_data.name, "udp_request")
  assert_eq(case_data.timestamp, "2026-09-16T09:00:00.123456")
  assert_eq(case_data.steps.length(), 1)
  assert_eq(case_data.steps[0].step_type, "send")
  assert_eq(case_data.steps[0].data, b"\xde\xad\xbe\xef")
  assert_true(!case_data.steps[0].truncated)
}
