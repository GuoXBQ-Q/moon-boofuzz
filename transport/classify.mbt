// SPDX-License-Identifier: GPL-2.0-only
// Semantic classification of raw OS socket error codes, mirroring the errno
// maps of boofuzz/connections/tcp_socket_connection.py at
// 518c13904fc32e7f2cc88c9dec934e509062953e: recv maps ECONNRESET/ENETRESET/
// ETIMEDOUT to reset and EWOULDBLOCK to a timeout, send adds EPIPE to the
// reset set, and connect treats ECONNREFUSED/EINPROGRESS/ETIMEDOUT as dial
// failures with EADDRINUSE as out-of-sockets. Windows (WSA) values are
// recognized alongside the POSIX errno numbers; the raw code is carried for
// exact reporting either way.

///|
pub(all) enum SocketFailure {
  Reset
  Aborted
  Refused
  TimedOut
  AddressInUse
  Other
} derive(Debug, Eq)

///|
pub fn classify_socket_failure(code : Int) -> SocketFailure {
  // ECONNRESET/ENETRESET/ETIMEDOUT/EPIPE (send) and their WSA counterparts.
  let reset = [104, 102, 110, 32, 10054, 10052, 10060]
  let aborted = [103, 10053]
  // ECONNREFUSED/EINPROGRESS as connect failures.
  let refused = [111, 115, 10061, 10036]
  // EWOULDBLOCK: timeout condition when using SO_RCVTIMEO/SO_SNDTIMEO.
  let timed_out = [11, 10035]
  let in_use = [98, 10048]
  if reset.contains(code) {
    Reset
  } else if aborted.contains(code) {
    Aborted
  } else if refused.contains(code) {
    Refused
  } else if timed_out.contains(code) {
    TimedOut
  } else if in_use.contains(code) {
    AddressInUse
  } else {
    Other
  }
}
