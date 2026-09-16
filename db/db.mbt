// SPDX-License-Identifier: GPL-2.0-only
// Safe sqlite3 wrappers. The error codes carried in DbError are raw SQLite
// result codes, mirroring how upstream surfaces sqlite3 exceptions.

///|
pub(all) suberror DbError {
  InvalidPath
  OpenFailure(Int)
  ExecFailure(Int)
  PrepareFailure(Int)
  BindFailure(Int)
  StepFailure(Int)
  NoSuchCase(Int)
} derive(Debug)

///|
pub struct Db {
  handle : DbHandle
}

///|
fn db_path_bytes(path : String) -> Bytes raise DbError {
  guard !path.is_empty() && !path.contains("\u{0}") else { raise InvalidPath }
  @utf8.encode(path)
}

///|
fn db_fail(code : Int) -> DbError {
  match code {
    1 => OpenFailure(code)
    2 => ExecFailure(code)
    3 => PrepareFailure(code)
    4 => BindFailure(code)
    5 => StepFailure(code)
    code => ExecFailure(code)
  }
}

///|
/// Open (creating if absent) a SQLite database file, the equivalent of
/// python's sqlite3.connect(path).
pub fn Db::open(path : String) -> Db raise DbError {
  let bytes = db_path_bytes(path)
  let handle = db_new()
  if db_open(handle, bytes, bytes.length()) != 0 {
    raise db_fail(db_error(handle))
  }
  { handle, }
}

///|
/// Run one or more semicolon-separated SQL statements without results.
pub fn Db::exec(self : Db, sql : String) -> Unit raise DbError {
  let bytes = @utf8.encode(sql)
  if db_exec(self.handle, bytes, bytes.length()) != 0 {
    raise ExecFailure(db_error(self.handle))
  }
}

///|
/// Prepare a parameterized statement for execution.
pub fn Db::prepare(self : Db, sql : String) -> Stmt raise DbError {
  let bytes = @utf8.encode(sql)
  let stmt = db_prepare(self.handle, bytes, bytes.length())
  if stmt_error(stmt) != 0 {
    raise PrepareFailure(stmt_error(stmt))
  }
  { handle: stmt, }
}

///|
pub fn Db::close(self : Db) -> Unit {
  ignore(db_close(self.handle))
}

///|
/// Create a uniquely named temporary file path (fixture helper).
pub fn temp_path() -> String {
  @utf8.decode_lossy(db_temp())
}

///|
pub fn remove_file(path : String) -> Unit {
  let bytes = @utf8.encode(path)
  db_remove(bytes, bytes.length())
}
