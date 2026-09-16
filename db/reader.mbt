// SPDX-License-Identifier: GPL-2.0-only
// Port of upstream fuzz_logger_db.FuzzLoggerDbReader at 518c139
// (fuzz_logger_db.py:233-289): case/step lookup, raw query and the failure
// map, reading databases written by either implementation.

///|
/// A test case as persisted in the `cases` table.
pub(all) struct DbCase {
  name : String
  index : Int
  timestamp : String
  steps : Array[DbStep]
} derive(Debug, Eq)

///|
/// One logged step as persisted in the `steps` table.
pub(all) struct DbStep {
  step_type : String
  description : String
  data : Bytes
  timestamp : String
  truncated : Bool
} derive(Debug, Eq)

///|
pub struct DbReader {
  db : Db
}

///|
fn value_text(value : DbValue, fallback : String) -> String {
  match value {
    VText(text) => text
    VBlob(bytes) => @utf8.decode_lossy(bytes)
    VInt(number) => number.to_string()
    VFloat(number) => number.to_string()
    VNull => fallback
  }
}

///|
fn value_int(value : DbValue, fallback : Int) -> Int {
  match value {
    VInt(number) => number.to_int()
    VFloat(number) => number.to_int()
    _ => fallback
  }
}

///|
fn value_bytes(value : DbValue) -> Bytes {
  match value {
    VBlob(bytes) => bytes
    VText(text) => @utf8.encode(text)
    _ => b""
  }
}

///|
fn value_bool(value : DbValue) -> Bool {
  match value {
    VInt(number) => number != 0L
    VText(text) => text == "true" || text == "True" || text == "1"
    VFloat(number) => number != 0.0
    _ => false
  }
}

///|
pub fn DbReader::open(path : String) -> DbReader raise DbError {
  { db: Db::open(path), }
}

///|
pub fn DbReader::close(self : DbReader) -> Unit {
  self.db.close()
}

///|
/// get_test_case_data: the case row plus its step rows, in insertion order.
/// A missing case raises NoSuchCase like upstream BoofuzzNoSuchTestCase
/// (fuzz_logger_db.py:244-249).
pub fn DbReader::get_test_case_data(
  self : DbReader,
  index : Int,
) -> DbCase raise DbError {
  let cases_stmt = self.db.prepare("SELECT * FROM cases WHERE number=?")
  defer cases_stmt.close()
  let case_rows = cases_stmt.query([VInt(index.to_int64())])
  guard case_rows.length() > 0 else { raise NoSuchCase(index) }
  let case_row = case_rows[0]
  // cases columns in table order: name, number, timestamp.
  let name = value_text(case_row.values[0], "")
  let timestamp = value_text(case_row.values[2], "")
  let steps_stmt = self.db.prepare(
    "SELECT * FROM steps WHERE test_case_index=?",
  )
  defer steps_stmt.close()
  let step_rows = steps_stmt.query([VInt(index.to_int64())])
  let steps : Array[DbStep] = []
  for row in step_rows {
    // steps columns: test_case_index, type, description, data, timestamp,
    // is_truncated.
    steps.push({
      step_type: value_text(row.values[1], ""),
      description: value_text(row.values[2], ""),
      data: value_bytes(row.values[3]),
      timestamp: value_text(row.values[4], ""),
      truncated: value_bool(row.values[5]),
    })
  }
  { name, index, timestamp, steps, }
}

///|
/// query: run raw SQL with positional parameters and return all rows. The
/// collection-based equivalent of upstream's cursor-returning query
/// (fuzz_logger_db.py:274-278).
pub fn DbReader::query(
  self : DbReader,
  sql : String,
  params? : Array[DbValue],
) -> Array[DbRow] raise DbError {
  let stmt = self.db.prepare(sql)
  defer stmt.close()
  stmt.query(params.unwrap_or([]))
}

///|
/// failure_map: test case index -> descriptions of its "fail" steps
/// (fuzz_logger_db.py:280-288).
pub fn DbReader::failure_map(
  self : DbReader,
) -> Map[Int, Array[String]] raise DbError {
  let rows = self.query("SELECT * FROM steps WHERE type='fail'")
  let map : Map[Int, Array[String]] = Map([])
  for row in rows {
    let index = value_int(row.values[0], 0)
    let description = value_text(row.values[2], "")
    match map.get(index) {
      Some(list) => list.push(description)
      None => map[index] = [description]
    }
  }
  map
}
