/* SPDX-License-Identifier: GPL-2.0-only
 * Minimal HTTP/1.1 serving bridge for the web UI. Mirrors the conventions
 * of transport/socket.c (opaque struct, error slot, per-object WSAStartup,
 * nonblocking fds, 0/-1/-2 returns) because separate native-stub
 * translation units cannot share the opaque socket struct. Loopback only,
 * matching upstream's default "localhost" web address.
 */
#include <moonbit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#define BF_WOULDBLOCK WSAEWOULDBLOCK
#define BF_INTR_ERR WSAEINTR
#else
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#define BF_WOULDBLOCK EAGAIN
#define BF_INTR_ERR EINTR
#endif

#ifdef _WIN32
typedef SOCKET bf_http_fd;
#else
typedef int bf_http_fd;
#endif

typedef struct {
#ifdef _WIN32
  SOCKET fd;
#else
  int fd;
#endif
  int error;
  int started;
} bf_http;

static int bf_web_errno(void) {
#ifdef _WIN32
  return WSAGetLastError();
#else
  return errno;
#endif
}

static void bf_web_shutdown_fd(bf_http *s) {
  if (s->fd != -1) {
#ifdef _WIN32
    closesocket(s->fd);
#else
    close(s->fd);
#endif
    s->fd = -1;
  }
#ifdef _WIN32
  if (s->started) { WSACleanup(); s->started = 0; }
#endif
}

static void bf_http_finalize(void *ptr) { bf_web_shutdown_fd((bf_http *)ptr); }

MOONBIT_FFI_EXPORT bf_http *bf_web_new(void) {
  bf_http *s = moonbit_make_external_object(bf_http_finalize, sizeof(bf_http));
  s->fd = -1;
  s->error = 0;
  s->started = 0;
#ifdef _WIN32
  /* The matching cleanup is per object so no process-global refcount leaks. */
  WSADATA data;
  s->error = WSAStartup(MAKEWORD(2, 2), &data);
  s->started = s->error == 0;
#endif
  return s;
}

MOONBIT_FFI_EXPORT int bf_web_error(bf_http *s) { return s->error; }

MOONBIT_FFI_EXPORT void bf_web_close(bf_http *s) { bf_http_finalize(s); }

/* fcntl/ioctlsocket helper for fds not owned by a bf_http yet. */
static int bf_web_nonblock_fd(bf_http_fd fd) {
#ifdef _WIN32
  u_long mode = 1;
  return ioctlsocket(fd, FIONBIO, &mode) == NO_ERROR ? 0 : -1;
#else
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) return -1;
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 ? 0 : -1;
#endif
}

static int bf_web_nonblock(bf_http *s) { return bf_web_nonblock_fd(s->fd); }

/* Bind 127.0.0.1:port (0 = OS-assigned) and listen; returns the bound
 * port so callers can implement the EADDRINUSE +1 retry of
 * sessions/session.py build_webapp_thread. */
MOONBIT_FFI_EXPORT int bf_web_listen(bf_http *s, int port) {
  if (s->error) return -1;
  bf_http_fd fd = socket(AF_INET, SOCK_STREAM, 0);
#ifdef _WIN32
  if (fd == INVALID_SOCKET) { s->error = bf_web_errno(); return -1; }
#else
  if (fd < 0) { s->error = bf_web_errno(); return -1; }
#endif
  struct sockaddr_in address; memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  address.sin_port = htons((unsigned short)port);
  if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 ||
      listen(fd, 8) != 0 ||
      bf_web_nonblock_fd(fd) != 0) {
    s->error = bf_web_errno();
#ifdef _WIN32
    closesocket(fd);
#else
    close(fd);
#endif
    return -1;
  }
  s->fd = fd;
#ifdef _WIN32
  int length = sizeof(address);
#else
  socklen_t length = sizeof(address);
#endif
  if (getsockname(s->fd, (struct sockaddr *)&address, &length) != 0) {
    s->error = bf_web_errno();
    return -1;
  }
  return ntohs(address.sin_port);
}

/* 0 = client connected, -1 = error, -2 = no pending connection. */
MOONBIT_FFI_EXPORT int bf_web_accept(bf_http *listener, bf_http *client) {
  if (listener->fd == -1) { return -1; }
  bf_http_fd fd = accept(listener->fd, NULL, NULL);
#ifdef _WIN32
  if (fd == INVALID_SOCKET) {
#else
  if (fd < 0) {
#endif
    int err = bf_web_errno();
    if (err == BF_WOULDBLOCK || err == BF_INTR_ERR) return -2;
    client->error = err;
    return -1;
  }
  if (bf_web_nonblock_fd(fd) != 0) {
#ifdef _WIN32
    closesocket(fd);
#else
    close(fd);
#endif
    return -1;
  }
  client->fd = fd;
  return 0;
}

/* 0 = ready, -1 = error, -2 = timeout expired. timeout_ms < 0 = forever. */
MOONBIT_FFI_EXPORT int bf_web_wait(bf_http *s, int writing, int timeout_ms) {
  if (s->fd == -1) return -1;
  struct timeval tv;
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;
  fd_set set;
  FD_ZERO(&set);
  FD_SET(s->fd, &set);
#ifdef _WIN32
  int result = select(0, writing ? NULL : &set, writing ? &set : NULL, NULL,
                      timeout_ms < 0 ? NULL : &tv);
#else
  int result = select(s->fd + 1, writing ? NULL : &set, writing ? &set : NULL,
                      NULL, timeout_ms < 0 ? NULL : &tv);
#endif
  if (result < 0) {
    int err = bf_web_errno();
    if (err == BF_INTR_ERR) return -2;
    s->error = err;
    return -1;
  }
  if (result == 0) return -2;
  return 0;
}

/* >0 bytes read, 0 = orderly close, -1 = error, -2 = would block. */
MOONBIT_FFI_EXPORT int bf_web_recv(bf_http *s, uint8_t *data, int length) {
  if (s->fd == -1) return -1;
  int n = (int)recv(s->fd, (char *)data, length, 0);
  if (n > 0) return n;
  if (n == 0) return 0;
  int err = bf_web_errno();
  if (err == BF_WOULDBLOCK || err == BF_INTR_ERR) return -2;
  s->error = err;
  return -1;
}

MOONBIT_FFI_EXPORT int bf_web_send(bf_http *s, const uint8_t *data, int length) {
  if (s->fd == -1) return -1;
  int total = 0;
  while (total < length) {
    int n = (int)send(s->fd, (const char *)data + total, length - total, 0);
    if (n < 0) {
      int err = bf_web_errno();
      if (err == BF_WOULDBLOCK || err == BF_INTR_ERR) {
        if (bf_web_wait(s, 1, 1000) != 0) { return -1; }
        continue;
      }
      s->error = err;
      return -1;
    }
    total += n;
  }
  return total;
}

/* Loopback client used by tests: 0 = connected, -1 = error (slot holds
 * the platform errno). The client is left nonblocking like server sides. */
MOONBIT_FFI_EXPORT int bf_web_connect(bf_http *s, int port) {
  if (s->error) return -1;
  bf_http_fd fd = socket(AF_INET, SOCK_STREAM, 0);
#ifdef _WIN32
  if (fd == INVALID_SOCKET) { s->error = bf_web_errno(); return -1; }
#else
  if (fd < 0) { s->error = bf_web_errno(); return -1; }
#endif
  struct sockaddr_in address; memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  address.sin_port = htons((unsigned short)port);
  if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
    s->error = bf_web_errno();
#ifdef _WIN32
    closesocket(fd);
#else
    close(fd);
#endif
    return -1;
  }
  s->fd = fd;
  if (bf_web_nonblock(s) != 0) {
    s->error = bf_web_errno();
    bf_web_shutdown_fd(s);
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int64_t bf_web_now_ms(void) {
#ifdef _WIN32
  return (int64_t)GetTickCount64();
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}
