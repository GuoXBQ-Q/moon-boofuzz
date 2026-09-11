# Portable JSONL records

`records.CaseRecord` is a pure Wasm/Native model. Version 1 stores case identity,
generator version, request path and mutation index, execution config, actual
accepted send bytes, responses, outcomes and failing step. All traffic bytes
are hexadecimal. `encode()` validates the model and produces one JSON object;
`decode()` rejects malformed hex, missing identity, unknown versions/properties
and inconsistent step paths.

`parse_jsonl_bytes` returns complete records plus an optional line-numbered
issue. An incomplete trailing line, invalid UTF-8 or malformed JSON is reported
without discarding preceding valid records. Even a syntactically valid last
JSON object must have its terminating newline to count as complete.

Native `recordio.Writer::open(path)` appends to a file and rejects a non-newline
tail. `append(record)` flushes every line; `close()` is idempotent. UTF-8 paths
use wide Windows file APIs. `recordio.capture(runner, writer)` stops the runner
at the first persistence failure and never executes the next case. Wrap the
writer in `defer writer.close()`. `read_records` defaults to a 64 MiB file cap,
adjustable with max_bytes, and reports oversized files explicitly.

Use `runner.record(result)` to snapshot its actual configuration and outcome.
Custom Channel factories are recorded as transport=custom and cannot be replayed
as TCP/UDP without a separately defined transport. No SQLite dependency is used.

Source: recording concepts from `boofuzz/fuzz_logger.py` and
`fuzz_logger_db.py`, baseline `518c13904fc32e7f2cc88c9dec934e509062953e`.
This JSONL schema and native file adapter are new GPL-2.0-only implementations,
not boofuzz database compatibility. Tests cover binary fidelity, partial tails,
unknown versions, file flushing and immediate runner stop after write failure.
