# 上游与来源记录

- 项目：boofuzz，Sulley 的后继项目。
- 地址：https://github.com/jtpereyda/boofuzz
- 研究分支：master。
- 固定基线：518c13904fc32e7f2cc88c9dec934e509062953e。
- 许可证：GPL-2.0-only（上游 LICENSE.txt 为 GPL v2 全文，pyproject.toml 声明 only）。
- 本仓库 LICENSE 从该基线 LICENSE.txt 原样复制。

| 本项目部分 | 参考范围 | 当前来源/兼容状态 |
| --- | --- | --- |
| Primitive | primitives 与协议定义文档的字段思想 | AI 辅助新实现；Static/Choice 不承诺完整上游行为 |
| Request | blocks/request.py 的请求建模思想 | AI 辅助新实现；仅平面字段与显式单字段变异 |
| 测试/示例 | 本项目构造的 PING、ASCII、零字节与 0xff 输入 | 未复制外部报文、数据集或上游 fixtures |
| 后续移植 | primitives、blocks、sessions、connections 的选定子集 | 尚未实施，实施时补充文件、版本和修改范围 |

## 1. Simple / Group

`field.mbt` follows `boofuzz/primitives/simple.py`, `group.py` and
`boofuzz/fuzzable.py` at the fixed revision above (GPL-2.0-only).
Supported: raw byte defaults, explicit candidates, Group default selection,
single-occurrence removal, duplicate preservation, and fuzzable=false.
String encodings and Group/block Cartesian products are not exposed.
`num_mutations` counts actual enumerated cases (zero when disabled), whereas
upstream `get_num_mutations` can still count disabled candidates.
The legacy Choice remains unchanged. `field_test.mbt` contains full small
oracle sequences, including binary values, rather than hashes of output.

Reproduce with `moon run scripts/oracle.mbtx ABSOLUTE_UPSTREAM EXPRESSION`.
The entry point verifies the upstream Git revision before invoking Python;
Python is only a development oracle, never a production dependency.
`scripts/fixtures.mbtx UPSTREAM INPUT_JSON OUTPUT_MBT` generates the committed
complete-byte tests from `fixtures/simple_group.json`; all three paths should
be absolute. It also rejects modifications to upstream source files.
For example, pass this expression as a single shell argument:

```python
[(p.render().hex(), [p.encode(m[0].value, None).hex() for m in p.get_mutations()]) for p in [Simple(default_value=b"A", fuzz_values=[b"", b"\x00\xff", b"\x00\xff"]), Group(values=[b"A",b"B",b"A",b"B"]), Group(values=[b"A",b"B",b"B"], default_value=b"B"), Group(values=[b"A"], default_value=b"C"), Group(values=[b"A",b"B"], fuzzable=False)]]
```

Expected `(default_hex, mutation_hex)` sequences:
`('41', ['', '00ff', '00ff'])`, `('41', ['42', '41', '42'])`,
`('42', ['41', '42'])`, `('43', ['41'])`, `('41', [])`.

Oracle-only dependencies follow upstream: pyserial (BSD), funcy (BSD),
pydot (MIT), pyparsing (MIT), tornado (Apache-2.0), attrs (MIT), click (BSD),
Flask (BSD), psutil (BSD), colorama (BSD). They are not linked or distributed
with the MoonBit library. `moonbitlang/async` (Apache-2.0) is used only by
developer `.mbtx` tooling; the production module has no new dependencies.

保留未来复制或翻译文件中的原版权和许可证声明，并注明修改。添加第三方算法、fixture 或依赖前单独核查其许可证；不将上游历史或 AI 生成内容冒充个人既有成果。维护者需要理解并复核 AI 辅助实现和测试。
