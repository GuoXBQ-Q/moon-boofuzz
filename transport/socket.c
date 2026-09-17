/* SPDX-License-Identifier: GPL-2.0-only
 * OS socket ABI bridge. Protocol/session policy lives in MoonBit.
 */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#pragma comment(lib, "ws2_32")
typedef SOCKET bf_fd;
#define BF_INVALID INVALID_SOCKET
#define bf_close_fd closesocket
#define bf_errno() WSAGetLastError()
#define BF_AGAIN WSAEWOULDBLOCK
#define BF_INTR WSAEINTR
#define BF_PROGRESS WSAEINPROGRESS
#else
#define _POSIX_C_SOURCE 200809L
#include <sys/socket.h>
#include <sys/select.h>
#include <poll.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
typedef int bf_fd;
#define BF_INVALID (-1)
#define bf_close_fd close
#define bf_errno() errno
#define BF_AGAIN EAGAIN
#define BF_INTR EINTR
#define BF_PROGRESS EINPROGRESS
#endif
#include <moonbit.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

typedef struct { bf_fd fd; int error; int started; int udp; int have_peer; struct sockaddr_in peer; } bf_socket;

/* WinSock is initialized once per process and never cleaned up: with
 * parallel tests, finalizers on one thread must never tear down WinSock
 * while another thread is using it (WSACleanup is process-global). */
static int g_bf_wsa_ready = 0;
static void bf_wsa_init(int *error_slot) {
#ifdef _WIN32
  if (!g_bf_wsa_ready) {
    WSADATA data;
    int rc = WSAStartup(MAKEWORD(2, 2), &data);
    if (rc == 0) { g_bf_wsa_ready = 1; }
    else if (*error_slot == 0) { *error_slot = rc; }
  }
#else
  (void)error_slot;
#endif
}

static void bf_reset(void *ptr) {
  bf_socket *s = ptr;
  if (s->fd != BF_INVALID) { bf_close_fd(s->fd); s->fd = BF_INVALID; }
}

static void bf_finalize(void *ptr) {
  bf_socket *s = ptr;
  bf_reset(s);
}

MOONBIT_FFI_EXPORT bf_socket *bf_new(void) {
  bf_socket *s = moonbit_make_external_object(bf_finalize, sizeof(bf_socket));
  s->fd = BF_INVALID; s->error = 0; s->started = 0; s->udp = 0; s->have_peer = 0; memset(&s->peer, 0, sizeof(s->peer));
  bf_wsa_init(&s->error);
  return s;
}

MOONBIT_FFI_EXPORT void bf_close(bf_socket *s) { bf_finalize(s); }
MOONBIT_FFI_EXPORT int bf_error(bf_socket *s) { return s->error; }

MOONBIT_FFI_EXPORT int64_t bf_now(void) {
#ifdef _WIN32
  return (int64_t)GetTickCount64();
#else
  struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

static int bf_nonblock(bf_fd fd) {
#ifdef _WIN32
  u_long yes = 1; return ioctlsocket(fd, FIONBIO, &yes);
#else
  int flags = fcntl(fd, F_GETFL, 0);
  return flags < 0 ? -1 : fcntl(fd, F_SETFL, flags | O_NONBLOCK);
#endif
}

MOONBIT_FFI_EXPORT int bf_wait(bf_socket *s, int writing, int timeout) {
  int64_t end = bf_now() + timeout;
  for (;;) {
    int64_t left = end - bf_now(); if (left < 0) left = 0;
#ifdef _WIN32
    struct timeval tv; tv.tv_sec = (long)(left / 1000); tv.tv_usec = (long)(left % 1000) * 1000;
    fd_set ready, errors; FD_ZERO(&ready); FD_ZERO(&errors);
    FD_SET(s->fd, &ready); FD_SET(s->fd, &errors);
    int result = select((int)(s->fd + 1), writing ? NULL : &ready, writing ? &ready : NULL, &errors, &tv);
#else
    struct pollfd descriptor; descriptor.fd = s->fd;
    descriptor.events = writing ? POLLOUT : POLLIN; descriptor.revents = 0;
    int result = poll(&descriptor, 1, (int)left);
#endif
    if (result >= 0) return result > 0 ? 1 : 0;
    s->error = bf_errno(); if (s->error != BF_INTR) return -1;
    if (bf_now() >= end) return 0;
  }
}

MOONBIT_FFI_EXPORT int bf_connect(bf_socket *s, const char *host, int port, int timeout, int udp) {
  if (s->error) return -1;
  struct addrinfo hints, *list = NULL; memset(&hints, 0, sizeof(hints));
  s->udp = udp;
  hints.ai_family = AF_UNSPEC; hints.ai_socktype = udp ? SOCK_DGRAM : SOCK_STREAM;
  char service[8]; snprintf(service, sizeof(service), "%d", port);
  int resolved = getaddrinfo(host, service, &hints, &list);
  if (resolved != 0) { s->error = resolved; return -1; }
  int result = -1; int64_t deadline = bf_now() + timeout;
  for (struct addrinfo *address = list; address; address = address->ai_next) {
    if (udp) {
      /* Unicast only: reject unspecified and multicast targets. */
      if (address->ai_family == AF_INET6) {
        struct sockaddr_in6 *six = (struct sockaddr_in6 *)address->ai_addr;
        if (IN6_IS_ADDR_UNSPECIFIED(&six->sin6_addr) || IN6_IS_ADDR_MULTICAST(&six->sin6_addr)) { result = -3; continue; }
      } else {
        uint32_t ip = ntohl(((struct sockaddr_in *)address->ai_addr)->sin_addr.s_addr);
        if (ip == 0 || ip >= 0xe0000000U) { result = -3; continue; }
      }
    }
    s->fd = socket(address->ai_family, udp ? SOCK_DGRAM : SOCK_STREAM, 0);
    if (s->fd == BF_INVALID) { s->error = bf_errno(); continue; }
    if (bf_nonblock(s->fd) != 0) { s->error = bf_errno(); bf_reset(s); continue; }
    if (connect(s->fd, address->ai_addr, (int)address->ai_addrlen) == 0) { result = 0; break; }
    s->error = bf_errno();
    if (s->error == BF_AGAIN || s->error == BF_PROGRESS) {
      int64_t left = deadline - bf_now();
      if (left <= 0) { result = -2; bf_reset(s); break; }
      int ready = bf_wait(s, 1, (int)left);
      if (ready == 0) { result = -2; bf_reset(s); break; }
      int error = 0;
#ifdef _WIN32
      int length = sizeof(error);
#else
      socklen_t length = sizeof(error);
#endif
      if (ready > 0 && getsockopt(s->fd, SOL_SOCKET, SO_ERROR, (char *)&error, &length) == 0 && error == 0) { result = 0; break; }
      s->error = error ? error : bf_errno();
    }
    bf_reset(s);
  }
  freeaddrinfo(list);
  if (result == 0) s->error = 0;
  return result;
}

MOONBIT_FFI_EXPORT int bf_send(bf_socket *s, const uint8_t *data, int offset, int length) {
#ifdef MSG_NOSIGNAL
  int flags = MSG_NOSIGNAL;
#else
  int flags = 0;
#endif
  int n = (int)send(s->fd, (const char *)data + offset, length, flags);
  if (n >= 0) return n;
  s->error = bf_errno();
  return s->error == BF_AGAIN || s->error == BF_INTR ? -2 : -1;
}

MOONBIT_FFI_EXPORT int bf_recv(bf_socket *s, uint8_t *data, int length) {
  int flags = 0;
#if !defined(_WIN32) && defined(MSG_TRUNC)
  if (s->udp) flags = MSG_TRUNC;
#endif
  int n = (int)recv(s->fd, (char *)data, length, flags);
  if (n > length) return -3;
  if (n >= 0) return n;
  s->error = bf_errno();
#ifdef _WIN32
  if (s->error == WSAEMSGSIZE) return -3;
#endif
  return s->error == BF_AGAIN || s->error == BF_INTR ? -2 : -1;
}

/* Loopback fixture syscalls; only private white-box tests call these. */
MOONBIT_FFI_EXPORT int bf_listen(bf_socket *s) {
  if (s->error) return -1;
  s->fd = socket(AF_INET, SOCK_STREAM, 0);
  if (s->fd == BF_INVALID) { s->error = bf_errno(); return -1; }
  struct sockaddr_in address; memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(s->fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(s->fd, 8) != 0 || bf_nonblock(s->fd) != 0) { s->error = bf_errno(); bf_close(s); return -1; }
#ifdef _WIN32
  int length = sizeof(address);
#else
  socklen_t length = sizeof(address);
#endif
  if (getsockname(s->fd, (struct sockaddr *)&address, &length) != 0) { s->error = bf_errno(); bf_close(s); return -1; }
  return ntohs(address.sin_port);
}

MOONBIT_FFI_EXPORT int bf_accept(bf_socket *listener, bf_socket *client) {
  client->fd = accept(listener->fd, NULL, NULL);
  if (client->fd == BF_INVALID || bf_nonblock(client->fd) != 0) { client->error = bf_errno(); bf_close(client); return -1; }
  return 0;
}

MOONBIT_FFI_EXPORT int bf_listen6(bf_socket *s) {
  if (s->error) return -1;
  s->fd = socket(AF_INET6, SOCK_STREAM, 0);
  if (s->fd == BF_INVALID) { s->error = bf_errno(); return -1; }
#ifdef _WIN32
  int v6only = 1;
  setsockopt(s->fd, IPPROTO_IPV6, IPV6_V6ONLY, (const char *)&v6only, sizeof(v6only));
#endif
  struct sockaddr_in6 address; memset(&address, 0, sizeof(address));
  address.sin6_family = AF_INET6; address.sin6_addr = in6addr_loopback;
  if (bind(s->fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(s->fd, 8) != 0 || bf_nonblock(s->fd) != 0) { s->error = bf_errno(); bf_close(s); return -1; }
#ifdef _WIN32
  int length = sizeof(address);
#else
  socklen_t length = sizeof(address);
#endif
  if (getsockname(s->fd, (struct sockaddr *)&address, &length) != 0) { s->error = bf_errno(); bf_close(s); return -1; }
  return ntohs(address.sin6_port);
}

MOONBIT_FFI_EXPORT int bf_port6(bf_socket *s) {
  struct sockaddr_in6 address;
#ifdef _WIN32
  int length = sizeof(address);
#else
  socklen_t length = sizeof(address);
#endif
  if (getsockname(s->fd, (struct sockaddr *)&address, &length) != 0) return -1;
  return ntohs(address.sin6_port);
}

MOONBIT_FFI_EXPORT int bf_bind_udp6(bf_socket *s) {
  if (s->error) return -1;
  s->udp = 1; s->fd = socket(AF_INET6, SOCK_DGRAM, 0);
  if (s->fd == BF_INVALID) return -1;
  struct sockaddr_in6 address; memset(&address, 0, sizeof(address));
  address.sin6_family = AF_INET6; address.sin6_addr = in6addr_loopback;
  if (bind(s->fd, (struct sockaddr *)&address, sizeof(address)) != 0 || bf_nonblock(s->fd) != 0) { bf_close(s); return -1; }
  return bf_port6(s);
}

MOONBIT_FFI_EXPORT int bf_udp6_receive_peer(bf_socket *s, uint8_t *data, int length) {
  struct sockaddr_in6 source;
#ifdef _WIN32
  int size = sizeof(source);
#else
  socklen_t size = sizeof(source);
#endif
  int n = (int)recvfrom(s->fd, (char *)data, length, 0, (struct sockaddr *)&source, &size);
  if (n < 0) return -1;
  if (connect(s->fd, (struct sockaddr *)&source, size) != 0) return -1;
  return n;
}

MOONBIT_FFI_EXPORT int bf_udp6_send_port(bf_socket *s, int port, const uint8_t *data, int length) {
  struct sockaddr_in6 address; memset(&address, 0, sizeof(address));
  address.sin6_family = AF_INET6; address.sin6_addr = in6addr_loopback; address.sin6_port = htons((uint16_t)port);
  return (int)sendto(s->fd, (const char *)data, length, 0, (struct sockaddr *)&address, sizeof(address));
}

MOONBIT_FFI_EXPORT int bf_port(bf_socket *s) {
  struct sockaddr_in address;
#ifdef _WIN32
  int length = sizeof(address);
#else
  socklen_t length = sizeof(address);
#endif
  if (getsockname(s->fd, (struct sockaddr *)&address, &length) != 0) return -1;
  return ntohs(address.sin_port);
}

MOONBIT_FFI_EXPORT int bf_bind_udp(bf_socket *s) {
  if (s->error) return -1;
  s->udp = 1; s->fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (s->fd == BF_INVALID) return -1;
  struct sockaddr_in address; memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(s->fd, (struct sockaddr *)&address, sizeof(address)) != 0 || bf_nonblock(s->fd) != 0) { bf_close(s); return -1; }
  return bf_port(s);
}

MOONBIT_FFI_EXPORT int bf_udp_receive_peer(bf_socket *s, uint8_t *data, int length) {
  struct sockaddr_in source;
#ifdef _WIN32
  int size = sizeof(source);
#else
  socklen_t size = sizeof(source);
#endif
  int n = (int)recvfrom(s->fd, (char *)data, length, 0, (struct sockaddr *)&source, &size);
  if (n < 0) return -1;
  if (connect(s->fd, (struct sockaddr *)&source, size) != 0) return -1;
  return n;
}

MOONBIT_FFI_EXPORT int bf_udp_send_port(bf_socket *s, int port, const uint8_t *data, int length) {
  struct sockaddr_in address; memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); address.sin_port = htons((uint16_t)port);
  return (int)sendto(s->fd, (const char *)data, length, 0, (struct sockaddr *)&address, sizeof(address));
}

MOONBIT_FFI_EXPORT void
bf_sleep(int ms) {
#ifdef _WIN32
  Sleep((DWORD)ms);
#else
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (long)(ms % 1000) * 1000000L;
  nanosleep(&ts, NULL);
#endif
}

/* ---- UDP server mode and broadcast (udp_socket_connection.py:36-133) ---- */

static int bf_parse_ipv4(const char *text, struct sockaddr_in *address) {
  memset(address, 0, sizeof(*address));
  address->sin_family = AF_INET;
#ifdef _WIN32
  address->sin_addr.s_addr = inet_addr(text);
  return address->sin_addr.s_addr != INADDR_NONE;
#else
  return inet_pton(AF_INET, text, &address->sin_addr) == 1;
#endif
}

/* Bind a UDP socket to host:port with SO_REUSEADDR, the server-mode
 * open() of udp_socket_connection.py:59-64. An empty host binds the
 * wildcard address (INADDR_ANY) and port 0 asks the OS for an ephemeral
 * port (read back with bf_udp_local_port). 0 = ok. */
MOONBIT_FFI_EXPORT int bf_udp_server(bf_socket *s, const uint8_t *host, int host_length, int port) {
  if (s->error) return -1;
  s->udp = 1;
  s->fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (s->fd == BF_INVALID) { s->error = bf_errno(); return -1; }
  struct sockaddr_in address;
  memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  if (host_length == 0) {
    address.sin_addr.s_addr = INADDR_ANY;
  } else {
    char *name = malloc((size_t)host_length + 1);
    if (name == NULL) { s->error = -1; bf_close_fd(s->fd); s->fd = BF_INVALID; return -1; }
    memcpy(name, host, (size_t)host_length); name[host_length] = 0;
    if (!bf_parse_ipv4(name, &address)) { free(name); s->error = -1; bf_close_fd(s->fd); s->fd = BF_INVALID; return -1; }
    free(name);
  }
  address.sin_port = htons((uint16_t)port);
#ifdef _WIN32
  int reuse = 1;
#else
  int reuse = 1;
#endif
  setsockopt(s->fd, SOL_SOCKET, SO_REUSEADDR, (const char *)&reuse, sizeof(reuse));
  if (bind(s->fd, (struct sockaddr *)&address, sizeof(address)) != 0 || bf_nonblock(s->fd) != 0) {
    s->error = bf_errno(); bf_close_fd(s->fd); s->fd = BF_INVALID; return -1;
  }
  return 0;
}

/* Local port of a bound UDP socket (ephemeral-port readback). Port number
 * or -1 on error. */
MOONBIT_FFI_EXPORT int bf_udp_local_port(bf_socket *s) {
  if (s->error || s->fd == BF_INVALID) return -1;
  struct sockaddr_in address;
#ifdef _WIN32
  int size = sizeof(address);
#else
  socklen_t size = sizeof(address);
#endif
  if (getsockname(s->fd, (struct sockaddr *)&address, &size) != 0) {
    s->error = bf_errno();
    return -1;
  }
  return (int)ntohs(address.sin_port);
}

/* Create the broadcast-mode datagram socket: SO_BROADCAST on an
 * unconnected socket (udp_socket_connection.py:52, :65-67). 0 = ok. */
MOONBIT_FFI_EXPORT int bf_udp_broadcast_enable(bf_socket *s) {
  if (s->error) return -1;
  s->udp = 1;
  s->fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (s->fd == BF_INVALID) { s->error = bf_errno(); return -1; }
  int enable = 1;
  if (setsockopt(s->fd, SOL_SOCKET, SO_BROADCAST, (const char *)&enable, sizeof(enable)) != 0 ||
      bf_nonblock(s->fd) != 0) {
    s->error = bf_errno(); bf_close_fd(s->fd); s->fd = BF_INVALID; return -1;
  }
  return 0;
}

/* recvfrom() that records the last peer, udp_socket_connection.py:70-100.
 * Oversized datagrams are consumed and reported as -3 (MSG_TRUNC gives the
 * real length on POSIX, WSAEMSGSIZE on Windows), matching the connected
 * path. >0/0 = datagram length, -2 = would block, -3 = too large,
 * -1 = error. */
MOONBIT_FFI_EXPORT int bf_udp_recvfrom(bf_socket *s, uint8_t *data, int length) {
  struct sockaddr_in source;
#ifdef _WIN32
  int size = sizeof(source);
#else
  socklen_t size = sizeof(source);
#endif
  int flags = 0;
#if !defined(_WIN32) && defined(MSG_TRUNC)
  flags = MSG_TRUNC;
#endif
  int n = (int)recvfrom(s->fd, (char *)data, length, flags, (struct sockaddr *)&source, &size);
  if (n > length) {
    s->peer = source;
    s->have_peer = 1;
    return -3;
  }
  if (n >= 0) {
    s->peer = source;
    s->have_peer = 1;
    return n;
  }
  int err = bf_errno();
#ifdef _WIN32
  if (err == WSAEMSGSIZE) { s->error = err; return -3; }
#endif
  if (err == BF_AGAIN || err == BF_INTR || err == BF_PROGRESS) return -2;
  s->error = err;
  return -1;
}

/* sendto() to the last recorded peer; send() of server mode
 * (udp_socket_connection.py:113-117). -3 = no peer recorded yet. */
MOONBIT_FFI_EXPORT int bf_udp_send_peer(bf_socket *s, const uint8_t *data, int length) {
  if (!s->have_peer) return -3;
  int n = (int)sendto(s->fd, (const char *)data, length, 0, (struct sockaddr *)&s->peer, sizeof(s->peer));
  if (n < 0) {
    int err = bf_errno();
    if (err == BF_AGAIN || err == BF_INTR || err == BF_PROGRESS) return -2;
    s->error = err;
    return -1;
  }
  return n;
}

/* Unconnected sendto() to any address — the broadcast send path
 * (udp_socket_connection.py:118-121). -4 = bad IPv4 literal. */
MOONBIT_FFI_EXPORT int bf_udp_send_address(bf_socket *s, const uint8_t *host, int host_length, int port, const uint8_t *data, int length) {
  char *name = malloc((size_t)host_length + 1);
  if (name == NULL) { s->error = -1; return -1; }
  memcpy(name, host, (size_t)host_length); name[host_length] = 0;
  struct sockaddr_in address;
  if (!bf_parse_ipv4(name, &address)) { free(name); return -4; }
  free(name);
  address.sin_port = htons((uint16_t)port);
  int n = (int)sendto(s->fd, (const char *)data, length, 0, (struct sockaddr *)&address, sizeof(address));
  if (n < 0) {
    int err = bf_errno();
    if (err == BF_AGAIN || err == BF_INTR || err == BF_PROGRESS) return -2;
    s->error = err;
    return -1;
  }
  return n;
}
