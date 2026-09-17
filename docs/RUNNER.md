# Sequential isolated cases

Import the Native `runner` package. `Runner::new(paths, endpoint, udp=false,
policies=..., limit=10000)` accepts compiled SessionPaths. Call `next()` for
one executed result at a time. Every case creates and closes a new connection,
sends default prerequisite requests in path order, then sends the mutated
target. A failed prerequisite prevents target transmission. Later cases start
with a new connection.

Policies are keyed by request name: `NoResponse` (default), `Fixed(n)`,
`Until(delimiter)` for TCP, or `Datagram` for UDP. Stream policies preserve
bytes beyond the boundary for subsequent responses. A single deadline covers
the whole response, including partial reads. Byte and case limits are explicit.
`stop()`, `state()` and `executed()` expose bounded execution progress.

Results carry a path-qualified identity, per-step actual accepted send bytes,
received bytes, completion flags and the failing step (-1 for connect).
`with_dialer` accepts a Channel factory for deterministic integration testing.
The factory must create a fresh channel; exceptions do not imply target crashes.

## Failure classification

A recorded outcome is a *counted failure* only when it matches upstream's
BoofuzzFailure or monitor log_fail: send failures, send timeouts, receive
failures, response mismatches, missing required data
(`NothingReceived`), oversized datagrams and configuration errors. Ignored
connection issues (`ConnectionIgnored`), receive timeouts, clean closes
(`PeerClosed`) and monitor callback errors (`CallbackFailed`) are recorded
for the report but do not count toward the crash thresholds and do not
trigger target recovery. A send reset/abort on the fuzzed node is ignored
by default (`ignore_connection_issues_when_sending_fuzz_data=true`, the
upstream default); prefix nodes honor `ignore_connection_reset` and
`ignore_connection_aborted` (default false). A receive reset/abort is
ignored unless `check_data_received` upgrades an empty read to
`NothingReceived`, like upstream's "Nothing received from target."
`receive_data_after_fuzz` performs one bounded read after the fuzzed node
under the default no-response policy; a configured read policy always wins.

## Dial failures, retries and crash thresholds

A dial-only failure (the connection was never established) takes the
reconnect path: the runner asks the monitor to recover the target, waits
`restart_sleep_ms` (default 5000) and retries, without running the post-case
failure machinery. `restart_threshold=None` (the default, and an explicit 0)
retries indefinitely like upstream's falsy check; an explicit positive
threshold counts failed dials including the first, and `restart_timeout_ms`
bounds the whole loop. Giving up ends the run after recording the failed
case (`state()` becomes `Stopped`), matching upstream re-raising out of the
fuzz loop. Dial failures never count toward the crash thresholds.

Case failures count per path (the fuzzed request, threshold 12) and per
mutating element (threshold 3). Reaching the element threshold exhausts the
element's remaining candidates and keeps the next element's first case;
reaching the path threshold exhausts only that path, and other paths keep
fuzzing. Monitor callbacks that raise are recorded as `CallbackFailed` but
are not counted failures and trigger no recovery; upstream logs callback
exceptions and keeps transmitting (see MONITORS.md).

## Start and end coordinates

`start` and `end` are global zero-based case ordinals across all paths, the
same coordinates as `generate --start`: cases below `start` are pulled but
never executed, and the run stops (`Limited`) once the next ordinal would
reach `end`. A sequential `start` beyond a path's case count carries into
the next path; combinatorial streams carry any unconsumed remainder forward.

Source: sequential single-case concepts, `_open_connection_keep_trying`
retry semantics and the crash-threshold counters of
`boofuzz/sessions/session.py` at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
MoonBit controls connection isolation and explicit response boundaries.
