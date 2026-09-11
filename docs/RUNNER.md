# Sequential isolated cases

Import the Native `runner` package. `Runner::new(paths, endpoint, udp=false,
policies=..., limit=10000)` accepts compiled SessionPaths. Call `next()` for
one executed result at a time. Every case creates and closes a new connection,
sends default prerequisite requests in path order, then sends the mutated
target. A failed prerequisite prevents target transmission. Later cases start
with a new connection. No failed case is retried automatically.

Policies are keyed by request name: `NoResponse` (default), `Fixed(n)`,
`Until(delimiter)` for TCP, or `Datagram` for UDP. Stream policies preserve
bytes beyond the boundary for subsequent responses. A single deadline covers
the whole response, including partial reads. Byte and case limits are explicit.
`stop()`, `state()` and `executed()` expose bounded execution progress.

Results carry a path-qualified identity, per-step actual accepted send bytes,
received bytes, completion flags and the failing step (-1 for connect).
`with_dialer` accepts a Channel factory for deterministic integration testing.
The factory must create a fresh channel; exceptions do not imply target crashes.

Source: sequential single-case concepts from `boofuzz/sessions/session.py`
at `518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
MoonBit controls connection isolation and explicit response boundaries.
