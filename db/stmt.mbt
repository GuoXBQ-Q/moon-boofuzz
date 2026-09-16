// SPDX-License-Identifier: GPL-2.0-only
// Prepared-statement wrapper plus the dynamic value type used by the
// reader's query equivalent.

///|
pub struct Stmt {
  handle : StmtHandle
}

///|
/// A value that can be bound to a statement parameter or returned in a row.
pub(all) enum DbValue {
  VNull
  VInt(Int64)
  VFloat(Double)
  VText(String)
  VBlob(Bytes)
} derive(Debug, Eq)

///|
/// One result row of a reader query, column values in order.
pub(all) struct DbRow {
  values : Array[DbValue]
} derive(Debug, Eq)

///|
fn bind_one(stmt : Stmt, index : Int, value : DbValue) -> Unit raise DbError {
  let failed = match value {
    VNull => stmt_bind_null(stmt.handle, index) != 0
    VInt(number) => stmt_bind_int64(stmt.handle, index, number) != 0
    VFloat(number) => stmt_bind_double(stmt.handle, index, number) != 0
    VText(text) => {
      let bytes = @utf8.encode(text)
      stmt_bind_text(stmt.handle, index, bytes, bytes.length()) != 0
    }
    VBlob(bytes) =>
      stmt_bind_blob(stmt.handle, index, bytes, bytes.length()) != 0
  }
  if failed {
    raise BindFailure(stmt_error(stmt.handle))
  }
}

///|
fn collect_row(stmt : Stmt) -> DbRow {
  let values : Array[DbValue] = []
  for column in 0..<stmt_column_count(stmt.handle) {
    if stmt_column_is_null(stmt.handle, column) == 1 {
      values.push(VNull)
    } else {
      match stmt_column_type(stmt.handle, column) {
        1 => values.push(VInt(stmt_column_int64(stmt.handle, column)))
        2 => values.push(VFloat(stmt_column_double(stmt.handle, column)))
        3 =>
          values.push(
            VText(@utf8.decode_lossy(stmt_column_bytes(stmt.handle, column))),
          )
        4 => values.push(VBlob(stmt_column_bytes(stmt.handle, column)))
        _ => values.push(VNull)
      }
    }
  }
  { values, }
}

///|
/// Bind parameters (1-based order) and return every result row, the
/// equivalent of draining a python cursor. Re-executing resets first, the
/// way python's cursor.execute does.
pub fn Stmt::query(
  self : Stmt,
  params : Array[DbValue],
) -> Array[DbRow] raise DbError {
  errdefer ignore(stmt_reset(self.handle))
  ignore(stmt_reset(self.handle))
  for i, value in params {
    bind_one(self, i + 1, value)
  }
  let rows : Array[DbRow] = []
  for ;; {
    let status = stmt_step(self.handle)
    if status == -1 {
      raise StepFailure(stmt_error(self.handle))
    }
    if status == 0 {
      break
    }
    rows.push(collect_row(self))
  }
  rows
}

///|
/// Execute without collecting rows (INSERT/UPDATE/DDL with parameters).
pub fn Stmt::run(self : Stmt, params : Array[DbValue]) -> Unit raise DbError {
  errdefer ignore(stmt_reset(self.handle))
  ignore(stmt_reset(self.handle))
  for i, value in params {
    bind_one(self, i + 1, value)
  }
  if stmt_step(self.handle) == -1 {
    raise StepFailure(stmt_error(self.handle))
  }
}

///|
pub fn Stmt::close(self : Stmt) -> Unit {
  stmt_close(self.handle)
}
