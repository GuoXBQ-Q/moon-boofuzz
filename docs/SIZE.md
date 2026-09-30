# Computed sizes

`Node::size("len", "request.body", length=4, endian=Little, offset=0,
inclusive=false, mutations=[])` encodes a block's current wire length.
Length is 1/2/4/8 bytes. With no explicit mutations, the field reproduces
upstream's delegation to an inner bit field: the full sorted boundary
sequence of the width (140 values for 16 bits, for example) replaces the
computed length, bypassing length calculation exactly like upstream.
Explicit `mutations` replace that automatic sequence. Math callbacks are
not exposed. The target must be a full block path.

Self-containing sizes are supported: measuring a parent counts the size field's
fixed width. As upstream does, inclusive=true adds that width again, even if
the target already contains the size field. Measuring never needs to render
a recursive size field. Ordinary cross-block size cycles, unknown references,
negative results and encoding overflow are errors. Offset arithmetic uses
Int64, and payload length changes are observed on every case.

Source: `boofuzz/blocks/size.py`, baseline
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
The dependency compiler and strict overflow errors are MoonBit adaptations.
`fixtures/size.json` regenerates `size_fixture_test.mbt`; request-level samples
compare the complete default and mutation payloads, including parent sizing,
Repeat and conditional switching. Upstream reference strings omit the request
prefix, while this API requires it explicitly.

## ASCII output（Content-Length 形态）

`Node::size(..., ascii=true)` / JSON `"ascii": true` 对应上游 `output_format="ascii"`
（size.py:41-48、examples/http_with_body.py）：计算出的长度渲染为**ASCII 十进制
文本**而非定宽二进制——HTTP `Content-Length:` 是典型用途，长度字段随 body 变异
实时跟随。宽度参数 `length` 退化为变异边界与溢出上限的位宽；默认变异序列
（无显式 `mutations` 且 fuzzable）同样按位宽边界生成，但以十进制文本渲染。
两个限制：ascii 模式不支持 `inclusive`（自身宽度随值变化，无法自计数）；
ascii size 不得位于其目标块内部（变宽自包含有歧义，编译期拒绝）。convert
页面对带单个未勾选 Content-Length 头的报文自动生成 `fuzzable: false` 的
ascii size 并把 body 包进命名块。
