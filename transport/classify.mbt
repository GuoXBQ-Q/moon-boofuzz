// SPDX-License-Identifier: GPL-2.0-only
// Semantic classification of raw OS socket error codes, mirroring the errno
// mapping in boofuzz/connections/tcp_socket_connection.py at
// 518c13904fc32e7f2cc88c9dec934e509062953e. Both Windows (WSA) and POSIX
// values are recognized; the code is carried for exact reporting either way.

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
  let reset = [10054, 104, 10052, 10038]
  let aborted = [10053, 103]
  let refused = [10061, 111, 10036, 10022]
  let timed_out = [10060, 110]
  let in_use = [10048, 98, 10013, 13]
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
