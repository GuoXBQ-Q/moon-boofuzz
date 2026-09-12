# 上游与来源记录

- 项目：boofuzz，Sulley 的后继项目。
- 地址：https://github.com/jtpereyda/boofuzz
- 研究分支：master。
- 固定基线：518c13904fc32e7f2cc88c9dec934e509062953e。
- 许可证：GPL-2.0-only（上游 LICENSE.txt 为 GPL v2 全文，pyproject.toml 声明 only）。
- 本仓库 LICENSE 从该基线 LICENSE.txt 原样复制。

| 本项目部分 | 参考范围 | 当前来源/兼容状态 |
| --- | --- | --- |
| Static / Choice / 平面 Request | 初始化自定义 API | 保留原行为；Choice 不冒充 Group |
| Simple / Group | primitives/simple.py、group.py、fuzzable.py | 字节候选、默认值与重复语义；fixtures/simple_group.json |
| 整数 | primitives/bit_field.py | 8/16/32/64 位二进制；完整边界序列样本；见 INTEGER.md |
| Bytes | primitives/bytes.py | 基础候选、魔术值、替换和长度处理；单字节 padding；见 BINARY.md |
| String / Delim | primitives/string.py、delim.py | 固定字符串库、确定性长字符串；动态 UTF-8 子集；见 TEXT.md |
| 命名块/变异流 | blocks/request.py、fuzzable_block.py | 不可变编译模型和惰性序列为 MoonBit 适配；见 MODEL.md、MUTATION.md |
| 条件/重复/对齐 | blocks/block.py、repeat.py、aligned.py | 条件子集、静态重复、整组对齐；见 CONDITIONS.md、REPEAT.md、ALIGNED.md |
| Size / CRC32 | blocks/size.py、checksum.py | 派生字段、自包含、显式错误值；请求级样本；见 SIZE.md、CHECKSUM.md |
| 会话 | sessions/session.py、pgraph/graph.py | DAG、插入顺序、末端目标变异；见 SESSION.md |
| TCP / UDP | connections/tcp_socket_connection.py、udp_socket_connection.py | 新写系统调用桥接；见 TRANSPORT.md、UDP.md |
| 回调与执行 | monitors/base_monitor.py、sessions/session.py | 顺序隔离、类型化结果；见 RUNNER.md、MONITORS.md |
| JSONL / 重放 / CLI | fuzz_logger.py、fuzz_logger_db.py 的记录概念 | 新格式和适配实现；见 RECORDS.md、REPLAY.md、DEFINITIONS.md |

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

移植文件保留基线、路径与许可说明。string_library.mbt 和 *_fixture_test.mbt 是固定上游生成的数据；fixtures/*.json 记录输入与来源，scripts/fixtures.mbtx 生成完整字节测试，CI 使用已提交样本。其余测试包含本项目构造的回环、二进制、错误路径和状态隔离场景。维护者需理解并复核 AI 辅助实现，不将上游历史或 AI 生成内容冒充个人既有成果。

## 工具链和发布范围

生产模块没有新增第三方模块依赖，没有内嵌网络运行时；Winsock/POSIX 和 C 标准文件 API 由系统提供。原本就依赖的 MoonBit 标准库和运行时使用 Apache-2.0，本次未把其源码或二进制复制到项目源码包。

Apache-2.0 与 GPL-2.0-only 不能被笼统认定为兼容，参见 [Apache 许可 FAQ](https://www.apache.org/foundation/license-faq.html)。正式分发合并二进制前，需要确认工具链组件的系统库例外或其他授权适用条件，参见 [GNU GPLv2 FAQ](https://www.gnu.org/licenses/old-licenses/gpl-2.0-faq.html)。本次准备的是项目源码包；此记录不等于已经取得合并二进制的额外分发许可。
