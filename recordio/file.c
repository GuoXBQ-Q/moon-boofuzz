/* SPDX-License-Identifier: GPL-2.0-only. File system ABI bridge only. */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
#endif
#include <moonbit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

typedef struct { FILE *file; int error; } bf_file;

static FILE *bf_fopen(const char *path, int write) {
#ifdef _WIN32
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
  if (!n) { errno = EINVAL; return NULL; }
  wchar_t *wide = malloc((size_t)n * sizeof(wchar_t));
  if (!wide) { errno = ENOMEM; return NULL; }
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, n);
  FILE *file = _wfopen(wide, write ? L"a+b" : L"rb");
  free(wide); return file;
#else
  return fopen(path, write ? "a+b" : "rb");
#endif
}

static void bf_file_finalize(void *ptr) {
  bf_file *f = ptr;
  if (f->file) { fclose(f->file); f->file = NULL; }
}

MOONBIT_FFI_EXPORT bf_file *bf_file_open(const char *path, int write) {
  bf_file *f = moonbit_make_external_object(bf_file_finalize, sizeof(bf_file));
  f->file = bf_fopen(path, write); f->error = f->file ? 0 : errno;
  if (write && f->file) {
    if (fseek(f->file, 0, SEEK_END) != 0) f->error = EIO;
    long size = ftell(f->file);
    if (size < 0) f->error = EIO;
    if (!f->error && size > 0) {
      if (fseek(f->file, -1, SEEK_END) != 0 || fgetc(f->file) != '\n') f->error = EINVAL;
      if (fseek(f->file, 0, SEEK_END) != 0) f->error = EIO;
    }
    if (f->error) bf_file_finalize(f);
  }
  return f;
}
MOONBIT_FFI_EXPORT int bf_file_error(bf_file *f) { return f->error; }
MOONBIT_FFI_EXPORT void bf_file_close(bf_file *f) { bf_file_finalize(f); }

MOONBIT_FFI_EXPORT int bf_file_write(bf_file *f, const uint8_t *bytes, int length) {
  if (!f->file || f->error) { if (!f->error) f->error = EBADF; return -1; }
  if (fwrite(bytes, 1, (size_t)length, f->file) != (size_t)length || fflush(f->file) != 0) { f->error = errno ? errno : EIO; return -1; }
  return 0;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t bf_file_read(bf_file *f, int maximum) {
  if (!f->file) { f->error = EBADF; return moonbit_make_bytes(0, 0); }
  if (fseek(f->file, 0, SEEK_END) != 0) { f->error = EIO; return moonbit_make_bytes(0, 0); }
  long n = ftell(f->file);
  if (n < 0 || n > maximum) { f->error = n < 0 ? EIO : EFBIG; return moonbit_make_bytes(0, 0); }
  if (fseek(f->file, 0, SEEK_SET) != 0) { f->error = EIO; return moonbit_make_bytes(0, 0); }
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)n, 0);
  if (fread(bytes, 1, (size_t)n, f->file) != (size_t)n) f->error = errno ? errno : EIO;
  return bytes;
}

/* Private fixture helpers create and remove a uniquely named temporary file. */
MOONBIT_FFI_EXPORT moonbit_bytes_t bf_file_temp(void) {
#ifdef _WIN32
  wchar_t dir[MAX_PATH], path[MAX_PATH];
  if (!GetTempPathW(MAX_PATH, dir) || !GetTempFileNameW(dir, L"mbf", 0, path)) return moonbit_make_bytes(0, 0);
  int n = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
  moonbit_bytes_t bytes = moonbit_make_bytes(n - 1, 0);
  WideCharToMultiByte(CP_UTF8, 0, path, -1, (char *)bytes, n, NULL, NULL);
  return bytes;
#else
  char path[] = "/tmp/moon-boofuzz-XXXXXX";
  int fd = mkstemp(path); if (fd < 0) return moonbit_make_bytes(0, 0); close(fd);
  int n = (int)strlen(path); moonbit_bytes_t bytes = moonbit_make_bytes(n, 0); memcpy(bytes, path, n); return bytes;
#endif
}
MOONBIT_FFI_EXPORT void bf_file_remove(const char *path) {
#ifdef _WIN32
  int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
  if (!n) return;
  wchar_t *wide = malloc((size_t)n * sizeof(wchar_t)); if (!wide) return;
  MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n); _wremove(wide); free(wide);
#else
  remove(path);
#endif
}
