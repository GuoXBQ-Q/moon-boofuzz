/* SPDX-License-Identifier: GPL-2.0-only
 * SQLite ABI bridge over the vendored public-domain amalgamation. Schema,
 * logging policy and reader logic live in MoonBit. Mirrors the conventions
 * of transport/socket.c and process/process.c: one opaque struct holding the
 * C handle plus an int error slot; 0 = success, -1 = failure (details in the
 * error slot), -2 = "row available" for step (parallel to process.c's
 * still-running poll result).
 */
#include <moonbit.h>
#include "sqlite3.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
#endif

typedef struct {
  sqlite3 *db;
  int error;
} bf_db;

typedef struct {
  sqlite3_stmt *stmt;
  sqlite3 *db;
  int error;
} bf_stmt;

static char *bf_copy_utf8(const uint8_t *bytes, int length) {
  char *text = (char*)malloc((size_t)length + 1);
  if (text != NULL) {
    memcpy(text, bytes, (size_t)length);
    text[length] = 0;
  }
  return text;
}

/* UTC ISO-8601 stamp matching upstream helpers.get_time_stamp():
 * datetime.now(timezone.utc).replace(tzinfo=None).isoformat(), which omits
 * the fractional part exactly when the microsecond count is zero. */
MOONBIT_FFI_EXPORT moonbit_bytes_t bf_db_now_iso(void) {
  long long seconds = 0;
  int micros = 0;
#ifdef _WIN32
  FILETIME now;
  GetSystemTimePreciseAsFileTime(&now);
  long long hundred_ns = ((long long)now.dwHighDateTime << 32) | now.dwLowDateTime;
  seconds = hundred_ns / 10000000LL - 11644473600LL;
  micros = (int)((hundred_ns / 10LL) % 1000000LL);
#else
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  seconds = (long long)ts.tv_sec;
  micros = (int)(ts.tv_nsec / 1000);
#endif
  time_t epoch = (time_t)seconds;
  struct tm parts;
#ifdef _WIN32
  gmtime_s(&parts, &epoch);
#else
  gmtime_r(&epoch, &parts);
#endif
  char stamp[64];
  if (micros == 0) {
    snprintf(stamp, sizeof(stamp), "%04d-%02d-%02dT%02d:%02d:%02d",
             parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday,
             parts.tm_hour, parts.tm_min, parts.tm_sec);
  } else {
    snprintf(stamp, sizeof(stamp), "%04d-%02d-%02dT%02d:%02d:%02d.%06d",
             parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday,
             parts.tm_hour, parts.tm_min, parts.tm_sec, micros);
  }
  int length = (int)strlen(stamp);
  moonbit_bytes_t bytes = moonbit_make_bytes(length, 0);
  memcpy(bytes, stamp, (size_t)length);
  return bytes;
}

static void bf_db_finalize(void *ptr) {
  bf_db *h = ptr;
  /* close_v2 tolerates unfinalized statements; the GC owns the object. */
  if (h->db != NULL) { sqlite3_close_v2(h->db); h->db = NULL; }
}

MOONBIT_FFI_EXPORT bf_db *bf_db_new(void) {
  bf_db *h = moonbit_make_external_object(bf_db_finalize, sizeof(bf_db));
  h->db = NULL;
  h->error = 0;
  return h;
}

MOONBIT_FFI_EXPORT int bf_db_error(bf_db *h) { return h->error; }

/* Open flags mirror python sqlite3.connect(): READWRITE | CREATE. */
MOONBIT_FFI_EXPORT int bf_db_open(bf_db *h, const uint8_t *path, int length) {
  char *name = bf_copy_utf8(path, length);
  if (name == NULL) { h->error = SQLITE_NOMEM; return -1; }
  if (h->db != NULL) { sqlite3_close_v2(h->db); h->db = NULL; }
  int rc = sqlite3_open_v2(name, &h->db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
  free(name);
  h->error = rc;
  return rc == SQLITE_OK ? 0 : -1;
}

MOONBIT_FFI_EXPORT int bf_db_close(bf_db *h) {
  if (h->db != NULL) {
    int rc = sqlite3_close_v2(h->db);
    h->db = NULL;
    if (rc != SQLITE_OK) { h->error = rc; return -1; }
  }
  return 0;
}

MOONBIT_FFI_EXPORT int bf_db_exec(bf_db *h, const uint8_t *sql, int length) {
  char *text = bf_copy_utf8(sql, length);
  if (text == NULL) { h->error = SQLITE_NOMEM; return -1; }
  int rc = sqlite3_exec(h->db, text, NULL, NULL, NULL);
  free(text);
  if (rc != SQLITE_OK) { h->error = rc; return -1; }
  return 0;
}

static void bf_stmt_finalize(void *ptr) {
  bf_stmt *s = ptr;
  if (s->stmt != NULL) { sqlite3_finalize(s->stmt); s->stmt = NULL; }
}

MOONBIT_FFI_EXPORT bf_stmt *bf_db_prepare(bf_db *h, const uint8_t *sql, int length) {
  bf_stmt *s = moonbit_make_external_object(bf_stmt_finalize, sizeof(bf_stmt));
  s->stmt = NULL;
  s->db = h->db;
  s->error = 0;
  char *text = bf_copy_utf8(sql, length);
  if (text == NULL) { s->error = SQLITE_NOMEM; return s; }
  int rc = sqlite3_prepare_v2(h->db, text, -1, &s->stmt, NULL);
  free(text);
  s->error = rc;
  return s;
}

MOONBIT_FFI_EXPORT int bf_stmt_error(bf_stmt *s) { return s->error; }

MOONBIT_FFI_EXPORT int bf_stmt_bind_int64(bf_stmt *s, int index, long long value) {
  int rc = sqlite3_bind_int64(s->stmt, index, (sqlite3_int64)value);
  if (rc != SQLITE_OK) { s->error = rc; return -1; }
  return 0;
}

MOONBIT_FFI_EXPORT int bf_stmt_bind_text(bf_stmt *s, int index, const uint8_t *value, int length) {
  int rc = sqlite3_bind_text(s->stmt, index, (const char*)value, length, SQLITE_TRANSIENT);
  if (rc != SQLITE_OK) { s->error = rc; return -1; }
  return 0;
}

MOONBIT_FFI_EXPORT int bf_stmt_bind_blob(bf_stmt *s, int index, const uint8_t *value, int length) {
  int rc = sqlite3_bind_blob(s->stmt, index, (const void*)value, length, SQLITE_TRANSIENT);
  if (rc != SQLITE_OK) { s->error = rc; return -1; }
  return 0;
}

MOONBIT_FFI_EXPORT int bf_stmt_bind_null(bf_stmt *s, int index) {
  int rc = sqlite3_bind_null(s->stmt, index);
  if (rc != SQLITE_OK) { s->error = rc; return -1; }
  return 0;
}

MOONBIT_FFI_EXPORT int bf_stmt_bind_double(bf_stmt *s, int index, double value) {
  int rc = sqlite3_bind_double(s->stmt, index, value);
  if (rc != SQLITE_OK) { s->error = rc; return -1; }
  return 0;
}

/* 0 = done (no more rows), -2 = row available, -1 = error (slot holds rc). */
MOONBIT_FFI_EXPORT int bf_stmt_step(bf_stmt *s) {
  int rc = sqlite3_step(s->stmt);
  if (rc == SQLITE_ROW) { return -2; }
  if (rc == SQLITE_DONE) { return 0; }
  s->error = rc;
  return -1;
}

MOONBIT_FFI_EXPORT int bf_stmt_reset(bf_stmt *s) {
  sqlite3_reset(s->stmt);
  sqlite3_clear_bindings(s->stmt);
  return 0;
}

MOONBIT_FFI_EXPORT void bf_stmt_close(bf_stmt *s) { bf_stmt_finalize(s); }

MOONBIT_FFI_EXPORT int bf_stmt_column_count(bf_stmt *s) {
  return sqlite3_column_count(s->stmt);
}

/* Raw sqlite3_column_type(): 1 integer, 2 float, 3 text, 4 blob, 5 null. */
MOONBIT_FFI_EXPORT int bf_stmt_column_type(bf_stmt *s, int column) {
  return sqlite3_column_type(s->stmt, column);
}

MOONBIT_FFI_EXPORT long long bf_stmt_column_int64(bf_stmt *s, int column) {
  return (long long)sqlite3_column_int64(s->stmt, column);
}

MOONBIT_FFI_EXPORT double bf_stmt_column_double(bf_stmt *s, int column) {
  return sqlite3_column_double(s->stmt, column);
}

MOONBIT_FFI_EXPORT int bf_stmt_column_is_null(bf_stmt *s, int column) {
  return sqlite3_column_type(s->stmt, column) == SQLITE_NULL ? 1 : 0;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t bf_stmt_column_bytes(bf_stmt *s, int column) {
  const void *data = sqlite3_column_blob(s->stmt, column);
  int length = sqlite3_column_bytes(s->stmt, column);
  if (data == NULL || length <= 0) { return moonbit_make_bytes(0, 0); }
  moonbit_bytes_t bytes = moonbit_make_bytes(length, 0);
  memcpy(bytes, data, (size_t)length);
  return bytes;
}

/* Private fixture helper: a uniquely named temporary file path. */
MOONBIT_FFI_EXPORT moonbit_bytes_t bf_db_temp(void) {
#ifdef _WIN32
  wchar_t dir[MAX_PATH], path[MAX_PATH];
  if (!GetTempPathW(MAX_PATH, dir) || !GetTempFileNameW(dir, L"mbd", 0, path)) return moonbit_make_bytes(0, 0);
  int n = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
  moonbit_bytes_t bytes = moonbit_make_bytes(n - 1, 0);
  WideCharToMultiByte(CP_UTF8, 0, path, -1, (char *)bytes, n, NULL, NULL);
  return bytes;
#else
  char path[] = "/tmp/moon-boofuzz-db-XXXXXX";
  int fd = mkstemp(path); if (fd < 0) return moonbit_make_bytes(0, 0); close(fd);
  int n = (int)strlen(path); moonbit_bytes_t bytes = moonbit_make_bytes(n, 0); memcpy(bytes, path, n); return bytes;
#endif
}

MOONBIT_FFI_EXPORT void bf_db_remove(const uint8_t *path, int length) {
  char *name = bf_copy_utf8(path, length);
  if (name == NULL) { return; }
#ifdef _WIN32
  int n = MultiByteToWideChar(CP_UTF8, 0, name, -1, NULL, 0);
  if (n > 0) {
    wchar_t *wide = (wchar_t*)malloc((size_t)n * sizeof(wchar_t));
    if (wide != NULL) {
      MultiByteToWideChar(CP_UTF8, 0, name, -1, wide, n);
      _wremove(wide);
      free(wide);
    }
  }
#else
  remove(name);
#endif
  free(name);
}
