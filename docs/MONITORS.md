# Case lifecycle and outcomes

Pass `Monitor::new(before=..., after=..., fault=..., recover=..., check=...)`
to a runner. Order is before, network/check operations, after, then fault and
recover if unsuccessful. Before failures prevent connecting. Per-response
checks may return false to reject a response; exceptions are callback failures.
Callbacks receive array snapshots so they cannot alter the runner's actual
send/receive record. Recovery false or exception stops the run immediately.

Outcomes distinguish connect/send/receive failures, each timeout phase, peer
closure, response mismatch, callback failure, configuration failure and recovery
failure. Socket failures never imply a crash. Callback/recovery error messages
retain the prior outcome. With default no-op callbacks, failed cases continue
using a new connection; the failed case itself is not retried.

Source: selected lifecycle ideas from `boofuzz/monitors/base_monitor.py` and
`boofuzz/sessions/session.py`, baseline
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
There is no process debugger or automatic crash detection in this subset.
