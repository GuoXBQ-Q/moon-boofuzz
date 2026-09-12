# JSON protocol definitions (schema version 1)

Top-level properties are schema_version=1, requests, optional edges, targets,
max_bytes (default 1048576), max_paths (default 10000), and execution.
Each request has name and children; blocks optionally have condition/alignment.
Edges are two-name arrays. Targets select final fuzzed requests. Unknown keys,
types, references and unsupported parameters are errors.

| type | Properties after type and name |
| --- | --- |
| static | value_hex |
| simple | value_hex, values_hex, fuzzable |
| group | values_hex, default_hex, fuzzable |
| integer | value (unsigned decimal **string**), width, endian, fuzzable |
| bytes | value_hex, size, max_len, padding_hex, fuzzable |
| text / delimiter | value (UTF-8 string), fuzzable |
| block | children, condition, alignment |
| repeat | target, min, max, step |
| size | target, length, endian, offset, inclusive, mutations (decimal strings) |
| crc32 | target, endian, mutations (decimal strings) |

Endianness is little/big. Conditions use field, op=eq/ne/in and value_hex or
values_hex. Alignment uses modulus and pattern_hex. References include the
request prefix. Integers use strings to preserve all 64 bits through JSON tools.
String size/encoding overrides are unsupported; binary field padding is one byte.

Execution contains transport=tcp/udp, endpoint with host/port and optional
connect_timeout_ms/send_timeout_ms/receive_timeout_ms/max_receive, policies by
request name, and case_limit. Policies use kind=none/fixed/until/datagram;
fixed adds length, until adds delimiter_hex. See examples/*.json.

Build with `moon build --target native cmd/boofuzz`, or run directly:

```text
moon run --target native cmd/boofuzz -- generate examples/offline.json --limit 3
moon run --target native cmd/boofuzz -- run examples/tcp.json --output tcp-cases.jsonl
moon run --target native cmd/boofuzz -- run examples/udp.json --output udp-cases.jsonl
```

Generate emits JSONL generated_case rows (including prefix_hex and payload_hex)
followed by generation_summary. --start skips raw candidate positions across
paths; --limit bounds output. Run overrides execution.case_limit with --limit
and records actual traffic. Open a fresh output file per run to avoid ambiguous
replay identities. All definitions/configuration are validated before connecting.

The schema/parser/CLI are new GPL-2.0-only adapters over the documented upstream
subset. JSON input cannot inject callbacks, shell commands or C pointers.
