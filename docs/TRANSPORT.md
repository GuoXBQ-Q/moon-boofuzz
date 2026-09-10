# Native TCP transport

Import `GuoXBQ-Q/moon-boofuzz/transport` from a Native package. Construct
`Endpoint::new("127.0.0.1", 8000)`, then `Connection::tcp(endpoint)` and ensure
`defer connection.close()` immediately after connecting. `send(bytes)` sends
the whole buffer under one deadline; `receive(max_bytes=...)` reads at most
that many bytes and returns `Data(bytes)` or `Closed` for TCP EOF.
Repeated close is harmless. A GC finalizer is a fallback for abandoned handles.
`last_sent_len()` returns the number of bytes accepted by the last send, also
after a partial failure. It does not claim the peer received or processed them.

Connection, send and receive timeouts default to 5000 ms. Each operation uses
a monotonic deadline, including partial sends and interrupted readiness waits.
Hostname/IPv4 is supported; IPv6 and TLS are not. The system `getaddrinfo`
resolver runs before the TCP connect deadline; OS name-resolution timing is
not controlled by this synchronous socket API. Use IPv4 when requiring a
strict end-to-end connection deadline. Receive defaults to 64 KiB and allows
an explicit cap up to 1 MiB; the API rejects invalid bounds before allocating.

C contains Winsock/POSIX calls, nonblocking readiness, handle finalizers and
error-code conversion. MoonBit owns the full-send loop, deadlines and errors.
The C layer borrows every buffer and never retains MoonBit pointers. Windows
handles pair WSAStartup with WSACleanup. Linux sends suppress SIGPIPE.

Source: behavior subset of `boofuzz/connections/tcp_socket_connection.py` and
`socket_connection.py` at `518c13904fc32e7f2cc88c9dec934e509062953e`, GPL-2.0-only.
The bridge is newly implemented against system headers; no networking runtime
dependency is added. Tests bind loopback port 0 and use bounded waits.
CI runs Wasm core and Native tests on Linux and Windows with MSVC.

Windows local development used a portable LLVM-MinGW toolchain with
`-D_CRT_RAND_S` and Winsock linking in its local configuration. The supported
Windows CI toolchain is MSVC; local MinGW success alone does not establish it.

Run `moon run scripts/asan.mbtx ABSOLUTE_PROJECT_ROOT` with GCC/Clang to
instrument the native test executable and bridge. The script restores package
configuration even on failure and uses a separate build directory. The current
MoonBit runtime uses the system allocator; no runtime file replacement is needed.
`scripts/native-info.mbtx` copies the compiler-generated native interface to
`docs/transport.native.mbti`, because the module's canonical backend is Wasm.
