/* SPDX-License-Identifier: GPL-2.0-only
 * CI diagnostics: on an unhandled exception (access violation etc.),
 * print the exception code, faulting address and owning module to stderr
 * before the process dies, so CI logs show where native crashes happen.
 * The constructor trick is per compiler: __attribute__ for GCC/clang,
 * .CRT$XCU allocation for MSVC.
 */
#include <stdio.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static LONG WINAPI bf_crash_filter(EXCEPTION_POINTERS *info) {
  void *address = info->ExceptionRecord->ExceptionAddress;
  HMODULE module = NULL;
  char name[MAX_PATH] = "?";
  if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         (LPCSTR)address, &module) &&
      GetModuleFileNameA(module, name, MAX_PATH) == 0) {
    lstrcpynA(name, "?", MAX_PATH);
  }
  fprintf(stderr, "bf-crash: code=0x%08lx addr=%p module=%s\n",
          (unsigned long)info->ExceptionRecord->ExceptionCode, address, name);
  fflush(stderr);
  return EXCEPTION_CONTINUE_SEARCH;
}

static void bf_crash_init(void) {
  SetUnhandledExceptionFilter(bf_crash_filter);
}

#if defined(__GNUC__)
__attribute__((constructor)) static void bf_crash_register(void) {
  bf_crash_init();
}
#else
static void bf_crash_init(void);
#pragma section(".CRT$XCU", read)
__declspec(allocate(".CRT$XCU")) static void (*bf_crash_register)(void) =
  bf_crash_init;
#endif
#endif
