# 用 MoonBit 代码编写 fuzz 脚本（CODE.md）

moon-boofuzz 的核心是 MoonBit 库：`CompiledRequest`/`SessionGraph`/`Runner` 就是上游
boofuzz `s_*` DSL + `Session` 的对应物。JSON 协议定义和 `convert` 页面只是这套 API
之上的序列化适配层——两条入口编译到同一个执行模型，行为完全同源。

本文从零走一遍：定义请求 → 离线枚举 → 会话 → 真实执行 → 监视器。完整可运行的
配套示例在 [cmd/httpfuzz](../cmd/httpfuzz/main.mbt)：

```sh
moon run --target native cmd/httpfuzz                      # 离线：打印前几个变异载荷
moon run --target native cmd/httpfuzz -- run 127.0.0.1 9000  # 真实 fuzz 一个 HTTP 服务
```

前提：安装 [MoonBit](https://www.moonbitlang.com/download/) 和 C 工具链（执行器与
网络 I/O 仅支持 Native；Windows 推荐 llvm-mingw 或 MSVC，Linux 用 GCC）。

## 第 1 步：包结构

在本仓库内新建一个可执行包（mooncakes 发布前外部项目无法引用本模块）：

```
cmd/httpfuzz/
├── moon.pkg
└── main.mbt
```

`moon.pkg`：

```
import {
  "GuoXBQ-Q/moon-boofuzz" @boofuzz,
  "GuoXBQ-Q/moon-boofuzz/runner",
  "GuoXBQ-Q/moon-boofuzz/transport",
  "moonbitlang/core/env",
  "moonbitlang/core/encoding/utf8",
}

supported_targets = "native"

pkgtype(kind: "executable")
```

## 第 2 步：定义请求（对应 s_* DSL）

字段按线上顺序放进命名 `Block`，每个可变异单元是一个命名 `Leaf` 节点：

```mbt nocheck
fn http_get() -> @boofuzz.CompiledRequest raise {
  @boofuzz.CompiledRequest::compile(
    @boofuzz.Block::new("get", [
      @boofuzz.Leaf("method", @boofuzz.Field::group([b"GET", b"POST", b"PUT"])),
      @boofuzz.Leaf("sp1", @boofuzz.Field::simple(b" ", [])),
      @boofuzz.Leaf("uri", @boofuzz.Field::text("/index.html")),
      @boofuzz.Leaf("sp2", @boofuzz.Field::simple(b" ", [])),
      @boofuzz.Leaf("version", @boofuzz.Field::text("HTTP/1.1", fuzzable=false)),
      @boofuzz.Leaf("crlf", @boofuzz.Field::simple(b"\r\n", [])),
      @boofuzz.Leaf("head", @boofuzz.Field::simple(b"Host: 127.0.0.1:9000\r\n", [])),
      @boofuzz.Leaf("end", @boofuzz.Field::delimiter("\r\n", fuzzable=false)),
    ]),
  )
}
```

与上游 `s_*` 的对应关系：

| boofuzz | moon-boofuzz | 说明 |
| --- | --- | --- |
| `s_initialize` + `s_block` | `Block::new` + `CompiledRequest::compile` | 编译时校验全部名字；嵌套 `Nested(Block)` |
| `s_static(b"...")` | `Field::simple(b"...")` | 候选为空 = 永不变异 |
| `s_string("...")` | `Field::text("...")` | 内置坏字符串库 + 重复变异 |
| `s_delim("...")` | `Field::delimiter("...")` | |
| `s_group([...])` | `Field::group([...])` | 首个值是默认值；变异轮换其余候选 |
| `s_int(v, size=4, endian="big")` | `Field::integer(v, width=32, endian=Big)` | width 单位是位（8/16/32/64），二进制渲染 |
| `s_bytes(...)` | `Field::binary(b"...", max_len=n)` | |
| `s_random` / `s_simple` | `Field::random_data` / `Field::simple` + 候选 | |
| `s_size` / `s_checksum` / `s_repeat` / `s_mirror` | `Node::size` / `Node::checksum` / `Node::repeat` / `Node::mirror` | |
| `s_block(dep=...)` / `s_aligned` | `Block::when(Condition)` / `Block::aligned` | |
| `s_from_file` | `Field::from_lines` | 自己读文件拆行；JSON 层无此类型 |

要点：

- 名字不能为空、不能含 `.` 或 `/`；字段路径带请求名前缀（如 `get.uri`）。
- `fuzzable=false` 的字段不产生用例，正常渲染时输出默认值。
- 显式候选写 `Field::simple(b"ok", [b"", b"\x00\xff"])`——候选**不会**自动混入
  默认值，与 JSON `values_hex` 语义一致。
- 所有字段构造器都接受 `fuzz_values=[...]` 追加自定义候选（见 PRIMITIVES.md）。

## 第 3 步：离线枚举

先不连目标，确认载荷符合预期（等价 `generate`）：

```mbt nocheck
let request = http_get()
println("total mutations: \{request.raw_mutation_count()}")
let stream = request.cases(limit=5)
for ;; {
  match stream.next() {
    Some(case) => println("\{case.id}: \{Repr(@utf8.decode_lossy(case.payload))}")
    None => break
  }
}
```

`CaseStream` 是惰性的：`next()` 逐个取用；`position()` 记录位置后可用
`cases(start=position)` 断点续跑；`stop()` 提前停止；`state()` 报告
running/exhausted/limited/stopped。多字段组合变异用
`request.combinatorial_cases(max_depth=n)`。

## 第 4 步：会话（多请求协议）

有握手/登录前缀时，用 `SessionGraph` 描述 DAG，只变异目标请求：

```mbt nocheck
let graph = @boofuzz.SessionGraph::new()
graph.add(hello)
graph.add(auth)
graph.add(query)
graph.connect("hello", "auth")
graph.connect("auth", "query")
let paths = graph.paths(targets=["query"])
```

`path.prefix()` 渲染全部前置请求（默认值）；执行时每个用例都在**新连接**上
先重发前置序列，再发送变异后的末端请求——与 JSON 路径的 `edges`/`targets`
语义一致。单请求协议跳过这步：`graph.paths(targets=["get"])`。

## 第 5 步：真实执行

```mbt nocheck
let endpoint = @transport.Endpoint::new("127.0.0.1", 9000, receive_timeout_ms=500)
let policies : Map[String, @runner.ReadPolicy] = Map([
  ("get", @runner.Until(b"\r\n\r\n")),   // 读到空行（响应头结束）
])
let runner = @runner.Runner::new(paths, endpoint, policies~, limit=20)
for ;; {
  match runner.next() {
    Some(result) => println("\{result.id} -> \{result.outcome.name()}")
    None => break
  }
}
```

- 读取策略按请求名配置：TCP 用 `NoResponse`（默认）/`Fixed(n)`/`Until(分隔符)`，
  UDP 用 `Datagram`。HTTP 响应用 `Until(b"\r\n\r\n")` 捕获响应头。
- `result.outcome.name()` 给出 passed/.receive_timeout/send_failure 等分类；
  失败详情在 `result.steps`（每步实际发送/接收字节）。
- **目标不在线时拨号默认无限重试**（上游 `restart_threshold=None` 语义）——
  先启动目标，或传 `restart_threshold=Some(3)`、`restart_timeout_ms=...`。
- 崩溃阈值默认：同一元素 3 次计失败用尽其候选，同一路径 12 次计失败放弃该路径。

## 第 6 步：监视器

进程监视器负责拉起目标、检测崩溃并重启（崩溃以 `MonitorFailed` 计入失败）：

```mbt nocheck
let monitor = @process.ProcessMonitor::new("python -m http.server 9000").monitor
let runner = @runner.Runner::new(paths, endpoint, policies~, monitor~, limit=20)
```

自定义响应检查用 `Monitor::new(after=...)`：回调返回 false 或抛出
`MonitorSignal::TargetFailed` 记为计失败；普通异常只记录不计数。完整语义见
MONITORS.md。

## 常见坑

- **每例一条新连接**：没有连接复用，HTTP 天然适配；有状态协议把握手放进
  `edges` 前置序列。
- **integer/bytes/random 二进制渲染**：fuzz 文本位置的数字段（如
  Content-Length）若要 ASCII 变异，用 `Field::text` 或显式候选。
- **候选不含默认值**：`Field::group` 从候选中移除一次默认值；
  `Field::simple` 的候选原样使用。
- **渲染上限 1 MiB**（`max_bytes` 可调）：超限报 `ModelError::Limit`，不静默截断。

## 文档地图

| 主题 | 文档 |
| --- | --- |
| 可执行 API 示例 | [README.mbt.md](../README.mbt.md) |
| 请求模型与命名规则 | [MODEL.md](MODEL.md) |
| 会话路径 | [SESSION.md](SESSION.md) |
| 执行器与失败分类 | [RUNNER.md](RUNNER.md) |
| 回调与监视器 | [MONITORS.md](MONITORS.md) |
| 原语精确语义 | [PRIMITIVES.md](PRIMITIVES.md)（及 TEXT/INTEGER/BINARY/SIZE/REPEAT/ALIGNED/CHECKSUM/CONDITIONS/VARIABLES） |
| 会话变量 | [VARIABLES.md](VARIABLES.md) |
| 记录/重放/报告 | [RECORDS.md](RECORDS.md) / [REPLAY.md](REPLAY.md) / [REPORT.md](REPORT.md) |
| 完整 API 签名 | 根目录 `pkg.generated.mbti` |
