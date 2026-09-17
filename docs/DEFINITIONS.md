# JSON protocol definitions (schema version 1)

## 快速修改现有定义

从 `examples/offline.json` 开始：`requests[].name` 是请求名，`children` 按顺序拼接字段。二进制值使用不带 `0x` 的十六进制字符串，如 `00ff`；`text`/`delimiter` 的 `value` 使用普通 UTF-8 文本。

```json
{
  "schema_version": 1,
  "requests": [{
    "name": "packet",
    "children": [
      {"type": "static", "name": "prefix", "value_hex": "50494e4720"},
      {"type": "simple", "name": "value", "value_hex": "6f6b", "values_hex": ["", "00ff", "6c6f6e67"]}
    ]
  }]
}
```

普通载荷为 `PING ok`；变异依次替换 `value`，得到 `PING `、`PING ` 加二进制 `00ff`、`PING long`。正常值不会自动增加为单独用例。给支持该选项的字段设置 `fuzzable: false`，会保留正常值并关闭其变异。

## 响应读取策略

`execution.policies` 的键是请求名，不是字段路径。未配置的请求使用 `none`。

| JSON | 适用传输 | 含义 |
| --- | --- | --- |
| `{"kind":"none"}` | TCP/UDP | 发送后不等待响应 |
| `{"kind":"fixed","length":2}` | TCP | 读取恰好 2 字节 |
| `{"kind":"until","delimiter_hex":"0d0a"}` | TCP | 读取到 CRLF，返回值包含分隔符 |
| `{"kind":"datagram"}` | UDP | 读取一个完整报文，包括空报文 |

例如给上述定义添加：

```json
"execution": {
  "transport": "tcp",
  "endpoint": {"host": "127.0.0.1", "port": 9000, "receive_timeout_ms": 100},
  "policies": {"packet": {"kind": "fixed", "length": 2}},
  "case_limit": 3
}
```

这段是顶层对象中的一个属性片段，需与 `requests` 之间加逗号。目标服务必须已经运行；它不回复时，`run` 会保存超时结果。`fixed` 和 `until` 对整次响应采用一个超时期限。

有前置流程时，参考 `examples/stateful.json` 的 `edges` 和 `targets`。每个用例都会重新执行完整前置序列，仅变异所选路径的末端请求。

## 格式参考

Top-level properties are schema_version=1, requests, optional edges, targets,
max_bytes (default 1048576), max_paths (default 10000), and execution.
Execution accepts transport (tcp/udp/file), endpoint, policies, case_limit,
udp_server, udp_broadcast, combinatorial, max_depth, variables,
check_data_received, receive_data_after_fuzz, ignore_connection_reset,
ignore_connection_aborted,
ignore_connection_issues_when_sending_fuzz_data (default true),
restart_threshold, restart_timeout_ms, restart_sleep_ms,
sleep_between_ms, crash_threshold_request, crash_threshold_element,
target_command, target_start_delay_ms, target_stop_delay_ms, and (file
transport) path. See docs/RUNNER.md for retry, threshold and failure
semantics.
Each request has name and children; blocks optionally have condition/alignment.
Edges are two-name arrays. Targets select final fuzzed requests. Unknown keys,
types, references and unsupported parameters are errors.

| type | Properties after type and name |
| --- | --- |
| static | value_hex, variable |
| simple | value_hex, values_hex, fuzzable, fuzz_values, variable |
| group | values_hex, default_hex, fuzzable, fuzz_values, variable |
| integer | value (unsigned decimal **string**), width, endian, fuzzable, fuzz_values, variable |
| bytes | value_hex, size, max_len, padding_hex, fuzzable, fuzz_values, variable |
| text / delimiter | value (UTF-8 string), fuzzable, fuzz_values, variable |
| block | children, condition, alignment, group (target field path; group-product case ids cannot be resumed by --id, use --start) |
| repeat | target, min, max, step, variable |
| size | target, length, endian, offset, inclusive, mutations (decimal strings), fuzzable |
| crc32 | target, endian, mutations (decimal strings), algorithm (crc32/crc32c/adler32/md5/sha1), fuzzable |
| mirror | target |
| random | value_hex, min_length, max_length, max_mutations, step, fuzzable, fuzz_values, variable |
| float | value (number), format (%.Nf), f_min, f_max (required numbers), max_mutations, seed (decimal string), ieee_754, endian, fuzzable, fuzz_values, variable |
| lines | lines (array of UTF-8 strings), max_len, fuzzable, fuzz_values, variable |

Every field type also accepts `fuzzable` and `fuzz_values` unless noted
(mirror has neither: it renders its target's current value). Endianness is
little/big. Conditions use field, op=eq/ne/in/not_in/gt/ge/lt/le and
value_hex or values_hex — the comparison variants keep upstream's operand
order quirk (`gt` renders when the field value is LESS than the configured
bytes). Alignment uses modulus and pattern_hex. References include the
request prefix. Integers use strings to preserve all 64 bits through JSON tools.
String size/encoding overrides are unsupported; binary field padding is one byte.

Execution contains transport=tcp/udp/file, endpoint with host/port and
optional connect_timeout_ms/send_timeout_ms/receive_timeout_ms/max_receive
(UDP server endpoints may use an empty host for the wildcard bind and port 0
for an ephemeral port), policies by request name, and case_limit. Policies
use kind=none/fixed/until/datagram; fixed adds length, until adds
delimiter_hex. The full execution key list is documented above; see
examples/*.json and docs/RUNNER.md.

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
