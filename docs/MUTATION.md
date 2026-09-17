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

## 已知差异:组合爆破的 skip 粒度(嵌套结构)

上游的组合爆破把 skip 过滤应用在 request 的**顶层条目**上
(`FuzzableBlock.mutations` 只比对顶层条目的 qualified_name),嵌套块内
字段的名称永远匹配不上顶层条目名,因此**不会被后续兄弟轮跳过**,会额外
产出"跨顺序"组合(如 `[b1:0,a1:0]` 与 `[a1:0,b1:0]` 两种顺序都发射,
载荷相同、序号不同)。本移植的组合流以叶子为单元按叶子过滤 skip 集,
扁平请求与上游逐例一致;嵌套请求在 depth≥2 时会比上游少产出这些重复
载荷的跨顺序用例。深度循环、相邻去重与累积 skip 的构造均与上游一致
(session.py:1132-1175、_mutations_contain_duplicate)。
