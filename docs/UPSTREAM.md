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
| Size 自动变异 / Checksum 边界 | blocks/size.py、blocks/checksum.py 的内嵌 BitField 委托与 6 条边界 | 已按上游实现；见 SIZE.md、CHECKSUM.md |
| 条件运算符 / 隐藏块发射 | blocks/block.py dep_compare 与条件不满足渲染空块 | 全部运算符与发射语义对齐（操作数顺序保留上游 quirk）；见 CONDITIONS.md |
| fuzz_values / RandomData / Float / FromFile / Mirror | primitives/*.py | fuzz_values 追加语义等价；随机序列 MT19937 逐位一致；个别计数 quirk 未复现并声明；见 PRIMITIVES.md、MODEL.md |
| Group+Block 笛卡尔 | blocks/block.py mutations 的 group 乘积 | 枚举顺序与用例数 n*(1+g) 一致；见 MODEL.md |
| 组合爆破 | sessions/session.py _generate_mutations_indefinitely | 深度循环/子串包含去重/累积 skip quirk 均对齐；MUTATION.md |
| 会话变量与动态重复 | protocol_session*.py、Repeat(variable=) | 内外双路径语义与 KeyError 对齐；见 VARIABLES.md |
| 进程监视器 | utils/process_monitor_local.py、utils/debugger_thread_simple.py | 无调试器子集：spawn/存活/故障/重启；见 PROCESS.md |
| 校验和算法集 | blocks/checksum.py 的算法表与 md5/sha1 字交换 | crc32/crc32c/adler32/md5/sha1 已接入节点与 JSON；ipv4/udp 以独立函数提供（块引用伪首部未接入）；见 CHECKSUM.md |
| IPv6 传输 | connections/base_socket_connection.py 的 getaddrinfo 双栈 | AF_UNSPEC 解析 + IPv6 单播校验；见 TRANSPORT.md、UDP.md |
| File 传输 | connections/file_connection.py | 每消息一个编号文件（截断创建），NoResponse 策略；见 DEFINITIONS.md file 传输 |
| CSV 导出 | fuzz_logger_csv.py | 行格式对齐（每用例一行 + 流量 hex）；见 RECORDS.md、cmd/boofuzz/csv_report.mbt |
| SQLite 结果库 | fuzz_logger_db.py | 表结构/写入队列/keep-only-n/512 截断/Reader 逐条对齐；vendor SQLite 3.45.3（公有领域）；见 DB.md |
| --record-passes 节流 | fuzz_logger_db.py num_log_cases（CLI record_passes） | SQLite 侧 num_log_cases + JSONL 侧 ThrottledWriter 等价实现；见 DB.md |
| Web UI 与 open | web/app.py、sessions/web_app.py、session_info.py、helpers.py 日志模板 | 回环 HTTP 服务、上游路由/JSON/日志行渲染/端口+1/暂停联动；open 支持 SQLite 与 JSONL；见 WEB.md |

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

生产模块没有新增第三方模块依赖，没有内嵌网络运行时；Winsock/POSIX 和 C 标准文件 API 由系统提供。原本就依赖的 MoonBit 标准库和运行时使用 Apache-2.0，本次未把其源码或二进制复制到项目源码包。例外：`db/sqlite3.c`、`db/sqlite3.h` 是 SQLite 3.45.3 amalgamation 的未修改副本——SQLite 源码为公有领域，进入本仓库不引入额外许可义务，也不属于上游 boofuzz 的分发物。

Apache-2.0 与 GPL-2.0-only 不能被笼统认定为兼容，参见 [Apache 许可 FAQ](https://www.apache.org/foundation/license-faq.html)。正式分发合并二进制前，需要确认工具链组件的系统库例外或其他授权适用条件，参见 [GNU GPLv2 FAQ](https://www.gnu.org/licenses/old-licenses/gpl-2.0-faq.html)。本次准备的是项目源码包；此记录不等于已经取得合并二进制的额外分发许可。
