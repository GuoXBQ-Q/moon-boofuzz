# Session paths

Create `SessionGraph::new()`, add compiled requests, then
`connect("handshake", "authentication")` and
`connect("authentication", "request")`.
`paths(targets=["request"])` snapshots the routes to selected targets.
Omitting targets selects every reachable request as a possible final target.
Roots follow node insertion order; branches follow edge insertion order.
Shared successors produce a separate path for each predecessor route.

`path.prefix()` renders only default prerequisite requests; `path.cases()`
mutates only the final target. Prefixes must be rerun on a fresh connection
for every case. The runner assigns path-qualified case identities.
Duplicate names/edges, unknown nodes and cycles raise typed model errors.
Path expansion is limited to 10,000 paths and 256 requests per path; excessive
expansion raises an error instead of returning a truncated array.

Source: DAG subset of graph traversal and request sequencing in
`boofuzz/sessions/session.py` and `boofuzz/pgraph/graph.py` at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
Cycles and Python callbacks on graph edges are not exposed. Session-level
`restart_interval` (periodic target restart every N cases) and the
`post_start_target`/`start_target` hook family have no port counterpart;
process lifecycle is owned by the process monitor (see PROCESS.md).
