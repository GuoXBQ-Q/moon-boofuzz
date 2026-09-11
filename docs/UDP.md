# UDP datagrams

`Connection::udp(endpoint)` uses a connected unicast IPv4 socket. Every
`send(bytes)` is one datagram, including zero-length input. Unlike TCP, it never
splits a request into chunks. Payloads over 65,507 bytes are rejected before
sending. Connected sockets discard datagrams from other source endpoints.

`receive()` returns one `Data` event, including `Data(b"")` for an empty
datagram. An oversized datagram relative to the receive buffer is consumed and
raises `DatagramTooLarge`; no truncated payload is reported as complete.
Linux uses `MSG_TRUNC`; Windows uses the returned `WSAEMSGSIZE` error. A
Windows SDK definition of MSG_TRUNC must not be passed as a recv input flag.
Timeout and system failure remain distinct. Broadcast, multicast, unspecified
destinations, IPv6 and server fuzzing are not supported.

Source: unicast semantics from `boofuzz/connections/udp_socket_connection.py`,
revision `518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
The implementation adds explicit empty-datagram and truncation handling.
Loopback tests cover binary/empty echo, timeout, source filtering, truncation
and an oversized send, using ephemeral ports and bounded waits.

CI initializes the MoonBit registry before invoking standalone `.mbtx` tools.
This fixes the clean-runner failure to resolve the developer-only async module;
the production module still has no async runtime dependency.
