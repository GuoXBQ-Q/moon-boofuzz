/* SPDX-License-Identifier: GPL-2.0-only
 * OS process ABI bridge. Monitor/session policy lives in MoonBit.
 * Mirrors the conventions of transport/socket.c: one opaque struct holding
 * an OS handle plus an int error slot; 0 = success, -1 = failure (details in
 * the error slot), -2 = retryable (the process has not exited yet).
 */
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <errno.h>
#endif

typedef struct {
#ifdef _WIN32
  HANDLE process;
  HANDLE thread;
#else
  int pid;
#endif
  int error;
  int exit_code;
  int exited;
} bf_proc;

static void bf_proc_finalize(void *ptr) {
  bf_proc *p = ptr;
#ifdef _WIN32
  if (p->process != NULL) { CloseHandle(p->process); p->process = NULL; }
  if (p->thread != NULL) { CloseHandle(p->thread); p->thread = NULL; }
#else
  if (p->pid > 0) {
    /* Best-effort reap; a still-running child is left to init. */
    int status = 0;
    if (waitpid(p->pid, &status, WNOHANG) == 0) { kill(p->pid, SIGKILL); }
  }
#endif
  /* The GC owns the object memory; only OS resources are released here. */
}

MOONBIT_FFI_EXPORT bf_proc *bf_proc_new(void) {
  bf_proc *p = moonbit_make_external_object(bf_proc_finalize, sizeof(bf_proc));
  memset(p, 0, sizeof(bf_proc));
#ifdef _WIN32
  p->process = NULL;
  p->thread = NULL;
#else
  p->pid = -1;
#endif
  return p;
}

MOONBIT_FFI_EXPORT int bf_proc_error(bf_proc *p) { return p->error; }

MOONBIT_FFI_EXPORT int bf_proc_is_windows(void) {
#ifdef _WIN32
  return 1;
#else
  return 0;
#endif
}

/* Spawn the UTF-8 command. On Windows the string is a full command line
 * handed to CreateProcessW; elsewhere it is shell text run through
 * /bin/sh -c (the same split upstream's DebuggerThreadSimple relies on). */
MOONBIT_FFI_EXPORT int bf_proc_spawn(bf_proc *p, uint8_t *command, int length) {
  if (length <= 0) { p->error = 0; return -1; }
#ifdef _WIN32
  int wide = MultiByteToWideChar(CP_UTF8, 0, (LPCCH)command, length, NULL, 0);
  if (wide <= 0) { p->error = (int)GetLastError(); return -1; }
  wchar_t *line = (wchar_t*)malloc((size_t)(wide + 1) * sizeof(wchar_t));
  if (line == NULL) { p->error = 8 /* ERROR_NOT_ENOUGH_MEMORY */; return -1; }
  MultiByteToWideChar(CP_UTF8, 0, (LPCCH)command, length, line, wide);
  line[wide] = 0;
  STARTUPINFOW start;
  PROCESS_INFORMATION info;
  ZeroMemory(&start, sizeof(start));
  ZeroMemory(&info, sizeof(info));
  start.cb = sizeof(start);
  if (!CreateProcessW(NULL, line, NULL, NULL, FALSE, 0, NULL, NULL, &start, &info)) {
    p->error = (int)GetLastError();
    free(line);
    return -1;
  }
  free(line);
  p->process = info.hProcess;
  p->thread = info.hThread;
  return 0;
#else
  char *text = (char*)malloc((size_t)length + 1);
  if (text == NULL) { p->error = ENOMEM; return -1; }
  memcpy(text, command, (size_t)length);
  text[length] = 0;
  pid_t pid = fork();
  if (pid < 0) { p->error = errno; free(text); return -1; }
  if (pid == 0) {
    execl("/bin/sh", "sh", "-c", text, (char*)NULL);
    _exit(127);
  }
  free(text);
  p->pid = (int)pid;
  return 0;
#endif
}

/* 0 = exited (exit code latched), -2 = still running, -1 = error. */
MOONBIT_FFI_EXPORT int bf_proc_poll(bf_proc *p) {
#ifdef _WIN32
  DWORD result = WaitForSingleObject(p->process, 0);
  if (result == WAIT_OBJECT_0) {
    DWORD code = 0;
    if (!GetExitCodeProcess(p->process, &code)) {
      p->error = (int)GetLastError();
      return -1;
    }
    p->exited = 1;
    p->exit_code = (int)code;
    return 0;
  }
  return -2;
#else
  int status = 0;
  pid_t done = waitpid((pid_t)p->pid, &status, WNOHANG);
  if (done == 0) { return -2; }
  if (done < 0) { p->error = errno; return -1; }
  p->exited = 1;
  if (WIFEXITED(status)) { p->exit_code = WEXITSTATUS(status); }
  else if (WIFSIGNALED(status)) { p->exit_code = 128 + WTERMSIG(status); }
  else { p->exit_code = -1; }
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int bf_proc_exit_code(bf_proc *p) { return p->exit_code; }

MOONBIT_FFI_EXPORT int bf_proc_pid(bf_proc *p) {
#ifdef _WIN32
  return (int)GetProcessId(p->process);
#else
  return p->pid;
#endif
}

MOONBIT_FFI_EXPORT int bf_proc_kill(bf_proc *p) {
#ifdef _WIN32
  if (!TerminateProcess(p->process, (UINT)1)) {
    p->error = (int)GetLastError();
    return -1;
  }
  return 0;
#else
  if (kill((pid_t)p->pid, SIGTERM) < 0) { p->error = errno; return -1; }
  return 0;
#endif
}
