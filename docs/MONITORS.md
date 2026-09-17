# Case lifecycle and outcomes

Pass `Monitor::new(before=..., after=..., fault=..., recover=..., check=...)`
to a runner. Order is before, network/check operations, after, then fault and
recover if unsuccessful. Before failures prevent connecting. Per-response
checks may return false to reject a response; exceptions are callback failures.
Callbacks receive array snapshots so they cannot alter the runner's actual
send/receive record. Recovery false or exception stops the run immediately.

Callback exceptions do not count as failures: like upstream, which logs
callback errors and keeps transmitting, the case is recorded as
`CallbackFailed` but no recovery runs and crash thresholds ignore it.
The one exception is `MonitorSignal::TargetFailed` raised from `after`,
which mirrors upstream's `post_send()` returning False: the case is
recorded as the counted failure `MonitorFailed`, drives fault/recover and
the crash thresholds — the process monitor reports target crashes this
way. Receive timeouts, clean closes and ignored connection resets are
likewise recorded without counting (see RUNNER.md for the full
classification).

Outcomes distinguish connect/send/receive failures, each timeout phase, peer
closure, response mismatch, callback failure, monitor-detected failure,
configuration failure and recovery failure. Socket failures never imply a
crash; a monitor-detected failure does. Callback error messages retain the
prior outcome in their text; a raising `fault` callback keeps the already
counted failure unchanged. With default no-op callbacks, failed cases
continue using a new connection; the failed case itself is not retried.

Source: selected lifecycle ideas from `boofuzz/monitors/base_monitor.py` and
`boofuzz/sessions/session.py`, baseline
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
There is no process debugger; the process monitor detects crashes by
liveness polling instead (see PROCESS.md).
