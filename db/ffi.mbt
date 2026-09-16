// SPDX-License-Identifier: GPL-2.0-only
// Raw sqlite3 externs over db/sqlite.c. Error convention: 0 = success,
// -1 = failure (result code in the handle's error slot), -2 = row available.

///|
type DbHandle

///|
extern "c" fn db_new() -> DbHandle = "bf_db_new"

///|
#borrow(handle, path)
extern "c" fn db_open(handle : DbHandle, path : Bytes, length : Int) -> Int = "bf_db_open"

///|
#borrow(handle)
extern "c" fn db_error(handle : DbHandle) -> Int = "bf_db_error"

///|
#borrow(handle)
extern "c" fn db_close(handle : DbHandle) -> Int = "bf_db_close"

///|
#borrow(handle, sql)
extern "c" fn db_exec(handle : DbHandle, sql : Bytes, length : Int) -> Int = "bf_db_exec"

///|
#borrow(handle, sql)
extern "c" fn db_prepare(
  handle : DbHandle,
  sql : Bytes,
  length : Int,
) -> StmtHandle = "bf_db_prepare"

///|
extern "c" fn now_iso() -> Bytes = "bf_db_now_iso"

///|
type StmtHandle

///|
#borrow(stmt)
extern "c" fn stmt_error(stmt : StmtHandle) -> Int = "bf_stmt_error"

///|
#borrow(stmt, value)
extern "c" fn stmt_bind_int64(
  stmt : StmtHandle,
  index : Int,
  value : Int64,
) -> Int = "bf_stmt_bind_int64"

///|
#borrow(stmt, value)
extern "c" fn stmt_bind_text(
  stmt : StmtHandle,
  index : Int,
  value : Bytes,
  length : Int,
) -> Int = "bf_stmt_bind_text"

///|
#borrow(stmt, value)
extern "c" fn stmt_bind_blob(
  stmt : StmtHandle,
  index : Int,
  value : Bytes,
  length : Int,
) -> Int = "bf_stmt_bind_blob"

///|
#borrow(stmt)
extern "c" fn stmt_bind_null(stmt : StmtHandle, index : Int) -> Int = "bf_stmt_bind_null"

///|
#borrow(stmt)
extern "c" fn stmt_bind_double(
  stmt : StmtHandle,
  index : Int,
  value : Double,
) -> Int = "bf_stmt_bind_double"

///|
#borrow(stmt)
extern "c" fn stmt_step(stmt : StmtHandle) -> Int = "bf_stmt_step"

///|
#borrow(stmt)
extern "c" fn stmt_reset(stmt : StmtHandle) -> Int = "bf_stmt_reset"

///|
#borrow(stmt)
extern "c" fn stmt_close(stmt : StmtHandle) -> Unit = "bf_stmt_close"

///|
#borrow(stmt)
extern "c" fn stmt_column_count(stmt : StmtHandle) -> Int = "bf_stmt_column_count"

///|
#borrow(stmt)
extern "c" fn stmt_column_type(stmt : StmtHandle, column : Int) -> Int = "bf_stmt_column_type"

///|
#borrow(stmt)
extern "c" fn stmt_column_int64(stmt : StmtHandle, column : Int) -> Int64 = "bf_stmt_column_int64"

///|
#borrow(stmt)
extern "c" fn stmt_column_double(stmt : StmtHandle, column : Int) -> Double = "bf_stmt_column_double"

///|
#borrow(stmt)
extern "c" fn stmt_column_is_null(stmt : StmtHandle, column : Int) -> Int = "bf_stmt_column_is_null"

///|
#borrow(stmt)
extern "c" fn stmt_column_bytes(stmt : StmtHandle, column : Int) -> Bytes = "bf_stmt_column_bytes"

///|
extern "c" fn db_temp() -> Bytes = "bf_db_temp"

///|
#borrow(path)
extern "c" fn db_remove(path : Bytes, length : Int) -> Unit = "bf_db_remove"
