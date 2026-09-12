# Streaming mutations

Call `compiled.cases(start=0, limit=10000)`, then `stream.next()` until `None`.
`MutationCase` includes payload bytes, field path, field mutation index,
global ordinal and a `v1:path:index` identity. Identities are stable for the
same named model and generator version; cross-version replay must save bytes.
Cases change one field at a time, in depth-first field order and candidate order.

`position()` is the next ordinal; create a new stream with that start to resume.
`stop()` ends this stream. `state()` distinguishes explicit stop, limit reached
and exhaustion. A rendering error stops the stream and raises its typed error.
Limits never truncate a payload. Construction and skipping do not render
mutation payloads; the white-box test uses a million-candidate generator to
verify only requested candidates are called.
The execution stream checks candidate byte-length metadata before allocation;
large binary padding and text/delimiter repetitions cannot bypass its byte cap.
`raw_mutation_count()` exposes cursor positions, including hidden candidates,
for generation start offsets across request paths.

Source: single-field ordering follows `boofuzz/fuzzable.py`,
`fuzzable_block.py` and `blocks/request.py` at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
The cursor, IDs and limit states are MoonBit APIs, not Python DSL emulation.
