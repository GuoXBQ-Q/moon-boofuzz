# moon-boofuzz

MoonBit 协议模糊测试核心：定义协议、生成单字段变异、执行前置会话、通过 TCP/UDP 发送、记录结果并重放。

采用 boofuzz 固定版本 `518c13904fc32e7f2cc88c9dec934e509062953e` 的明确功能子集；核心支持 Wasm 与 Native，网络和文件 I/O 支持 Windows/Linux Native。已发布到 [mooncakes.io](https://mooncakes.io/docs/GuoXBQ-Q/moon-boofuzz)（页面显示最新版本）；支持范围与兼容边界见 [UPSTREAM.md](docs/UPSTREAM.md)。

## 前置环境

- 安装 [MoonBit](https://www.moonbitlang.com/download/)。纯逻辑核心（协议模型与变异枚举）在 Wasm 下即可使用，无需 C 环境。
- 网络与文件 I/O 仅支持 Native，需要系统 C 编译器：Windows 推荐 [llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases)（把 bin 加入 PATH）或 Visual Studio MSVC，Linux 使用 GCC。当前验证工具链为 moon 0.1.20260920、moonc v0.10.14。

## 使用示例

### 1. 直接安装 CLI 使用

无需克隆仓库（需本机 C 编译器），从 mooncakes 全局安装：

```sh
moon install GuoXBQ-Q/moon-boofuzz/cmd/boofuzz   # 主 CLI，装到 ~/.moon/bin
moon install GuoXBQ-Q/moon-boofuzz/cmd/httpd     # 可选：自带 HTTP fuzz 靶子
```

httpd 是一个严格解析的回环 HTTP 服务器，对畸形输入返回明确的拒绝状态码（431/413/405 等），让 fuzzer 能区分"被拒绝"和"连接被丢弃"。

保存协议定义 `http.json`（与仓库 [examples/http.json](examples/http.json) 相同——只有 `uri` 字段开启变异，其余请求行/头部字节全部冻结，完整枚举共 1954 个用例）：

```json
{
  "schema_version": 1,
  "requests": [{
    "name": "request",
    "children": [
      {"type": "text", "name": "method", "value": "GET", "fuzzable": false},
      {"type": "static", "name": "sp1", "value_hex": "20"},
      {"type": "text", "name": "uri", "value": "/index.html", "fuzzable": true},
      {"type": "static", "name": "sp2", "value_hex": "20"},
      {"type": "text", "name": "version", "value": "HTTP/1.1", "fuzzable": false},
      {"type": "static", "name": "crlf0", "value_hex": "0d0a"},
      {"type": "static", "name": "name_0", "value_hex": "486f73743a20"},
      {"type": "text", "name": "hdr_0", "value": "127.0.0.1:9000", "fuzzable": false},
      {"type": "static", "name": "crlf1", "value_hex": "0d0a"},
      {"type": "static", "name": "name_1", "value_hex": "557365722d4167656e743a20"},
      {"type": "text", "name": "hdr_1", "value": "moon-boofuzz", "fuzzable": false},
      {"type": "static", "name": "crlf2", "value_hex": "0d0a"},
      {"type": "static", "name": "name_2", "value_hex": "436f6e6e656374696f6e3a20"},
      {"type": "text", "name": "hdr_2", "value": "close", "fuzzable": false},
      {"type": "static", "name": "crlf3", "value_hex": "0d0a"},
      {"type": "static", "name": "head_end", "value_hex": "0d0a"},
      {"type": "text", "name": "body", "value": "", "fuzzable": false}
    ]
  }],
  "execution": {
    "transport": "tcp",
    "endpoint": {"host": "127.0.0.1", "port": 9000, "receive_timeout_ms": 500},
    "policies": {"request": {"kind": "until", "delimiter_hex": "0d0a0d0a"}}
  }
}
```

靶子有两种启动方式，任选其一：

**方式 A · 手动启动**：另开一个终端单独运行靶子，fuzz 命令只负责发送。

```sh
# 终端 1：启动靶子
httpd --port 9000
# httpd listening on 127.0.0.1:9000

# 终端 2：执行 fuzz
boofuzz run http.json --output cases.jsonl
```

**方式 B · `--target-cmd` 一条命令**：boofuzz 自己孵化靶子并开启**进程监视**——开跑前自动拉起（含约 1 秒启动延迟），运行期内靶子的任何退出（包括正常退出 0）都会把该用例记为 `MonitorFailed` 故障、自动重启靶子后续跑，结束后子进程自动回收，全程无需另开终端。命令含空格时整体加引号。

```sh
boofuzz run http.json --output cases.jsonl --target-cmd "httpd --port 9000"
```

崩溃监视的实战效果可用仓库的 [examples/httpd_lab.json](examples/httpd_lab.json) 体验（模拟 RCE 与缓冲区溢出的崩溃注入场景；注意其 execution 自带 `"case_limit": 6`）。

两种方式下 `run` 的行为相同：逐例变异发送，把真实收发字节写入 JSONL 和 `boofuzz-results/` 下的 SQLite 结果库。启动时会打印实时 Web 界面地址，**fuzz 过程中用浏览器打开它即可查看进度**：

```text
Web interface can be found at http://localhost:26000
```

页面提供进度条（当前用例 / 总数）、运行速率、崩溃列表和暂停/恢复按钮（暂停会挂起用例循环），失败或崩溃条目可点进 `/test-case/<n>` 查看逐例日志。`--web-port N` 可改端口（被占用时自动顺延，`0` 为随机空闲端口）。对本地 httpd 全速约 80 例/秒，此定义完整跑约 25 秒，结束时输出汇总：

```text
{"kind":"run_summary","executed":1954,"state":"exhausted","records":"cases.jsonl","database":"boofuzz-results/run-<UTC时间戳>.db"}
```

**分析结果**（每条记录包含完整的收发字节，1954 例约 117 MB；`report` 默认可读约 2 GiB 以内的文件，超过时按报错提示处理）：

```sh
boofuzz report cases.jsonl
```

```text
{"kind":"report","summary":{"total":1954,"outcomes":{"passed":1947,"connection_ignored":7},
 "failures":[{"line":240,"case_id":"[\"request\"]/v1:request.uri:239","outcome":"connection_ignored",
 "failed_step":0,"detail":"ConnectionIgnored(\"send reset/aborted at step 0\")"}, ...]},"error":null}
```

**从源码使用**（想阅读/修改工具本身时）：克隆仓库后先 `moon update` 初始化依赖索引，`moon check --deny-warn` 做全量类型检查，`moon build --target native` 构建全部可执行（CLI、httpd 靶子等），`moon test --target native --deny-warn` 跑完整测试（含临时文件、回环地址和临时端口、无需另启服务的自动验收场景）；此后所有子命令的等价写法是 `moon run --target native cmd/boofuzz -- <子命令> ...`。

### 2. 作为库使用（MoonBit API）

以 [examples/http_get_full](examples/http_get_full/main.mbt)（头部丰富的 HTTP GET 变异，与 `examples/http_get_full.json` 等价）为蓝本的精简版。在自己的模块 `moon add GuoXBQ-Q/moon-boofuzz` 后，新建可执行包 `cmd/main`：

`cmd/main/moon.pkg`：

```
import {
  "GuoXBQ-Q/moon-boofuzz" @boofuzz,
  "GuoXBQ-Q/moon-boofuzz/runner",
  "GuoXBQ-Q/moon-boofuzz/transport",
}

supported_targets = "native"

pkgtype(kind: "executable")
```

`cmd/main/main.mbt`：

```moonbit nocheck
///|
/// 冻结的结构字节：空格、CRLF、头名，永不变异。
fn fixed(bytes : Bytes) -> @boofuzz.Field {
  @boofuzz.Field::simple(bytes, [], fuzzable=false)
}

///|
/// 请求行 + Host/Accept/X-Fuzz 头。变异点：动词组（GET/HEAD）、
/// URI 显式候选、两个字符串库字段。
fn http_get() -> @boofuzz.CompiledRequest raise {
  @boofuzz.CompiledRequest::compile(
    @boofuzz.Block::new("http_get", [
      @boofuzz.Leaf("verb", @boofuzz.Field::group([b"GET", b"HEAD"])),
      @boofuzz.Leaf("sp1", fixed(b" ")),
      @boofuzz.Leaf(
        "uri",
        @boofuzz.Field::simple(b"/", [b"/echo", b"/headers", b"/nope"]),
      ),
      @boofuzz.Leaf("sp2", fixed(b" ")),
      @boofuzz.Leaf("version", fixed(b"HTTP/1.1")),
      @boofuzz.Leaf("crlf0", fixed(b"\r\n")),
      @boofuzz.Leaf("host", fixed(b"Host: 127.0.0.1:9000\r\n")),
      @boofuzz.Leaf("accept_name", fixed(b"Accept: ")),
      @boofuzz.Leaf("accept", @boofuzz.Field::text("application/json")),
      @boofuzz.Leaf("crlf1", fixed(b"\r\n")),
      @boofuzz.Leaf("xfuzz_name", fixed(b"X-Fuzz: ")),
      @boofuzz.Leaf("xfuzz", @boofuzz.Field::text("seed")),
      @boofuzz.Leaf("crlf2", fixed(b"\r\n")),
      @boofuzz.Leaf("head_end", fixed(b"\r\n")),
    ]),
  )
}

///|
fn main raise {
  let request = http_get()
  let graph = @boofuzz.SessionGraph::new()
  graph.add(request)
  let paths = graph.paths(targets=["http_get"])
  let endpoint = @transport.Endpoint::new(
    "127.0.0.1",
    9000,
    connect_timeout_ms=750,
    receive_timeout_ms=750,
  )
  // 读到 HTTP 头结束为止；每例新建连接。
  let policies : Map[String, @runner.ReadPolicy] = Map([
    ("http_get", @runner.Until(b"\r\n\r\n")),
  ])
  let runner = @runner.Runner::new(
    paths,
    endpoint,
    policies~,
    limit=@runner.NO_CASE_LIMIT,
    restart_threshold=Some(1),
    restart_sleep_ms=0,
  )
  for ;; {
    match runner.next() {
      Some(result) =>
        println(
          "\{result.case.field_path}:\{result.case.mutation_index} -> \{result.outcome.name()}",
        )
      None => break
    }
  }
}
```

对着 httpd 靶子运行（先按上面方式启动 `httpd --port 9000`）：

```sh
moon run --target native cmd/main
```

输出形如 `uri:1 -> timeout`、`verb:0 -> ...` 的逐例结果。完整版（参数化 host/port、离线生成模式、Web UI 实时面板与暂停）见 [examples/http_get_full/main.mbt](examples/http_get_full/main.mbt)；从零编写自己的 fuzz 程序见 [CODE.md](docs/CODE.md) 教程，模型与字段原语见 [MODEL.md](docs/MODEL.md)，会话与执行器细节见 [SESSION.md](docs/SESSION.md)、[RUNNER.md](docs/RUNNER.md) 与 [MONITORS.md](docs/MONITORS.md)。

## boofuzz 命令简介

`boofuzz` 的子命令围绕"定义 → 执行 → 分析/重放"组织（源码仓库内的等价写法是 `moon run --target native cmd/boofuzz -- <子命令> ...`）：

| 命令 | 用途 |
| --- | --- |
| `boofuzz generate DEFINITION.json` | JSON 协议定义 → 变异载荷 JSONL，不连接目标 |
| `boofuzz run DEFINITION.json --output CASES.jsonl` | 逐例执行并保存实际流量；`--target-cmd CMD` 可让 boofuzz 自己孵化并监视靶子（崩溃记为 fault 并自动重启），`--web-port N` 控制实时界面端口 |
| `boofuzz report CASES.jsonl` | 分类计数、失败身份和行号 |
| `boofuzz replay CASES.jsonl --id CASE_ID` | 按身份重放保存的字节，可用 `--host/--port` 覆盖目标 |
| `boofuzz open FILE` | 结果库/JSONL → 本地只读 Web 视图 |
| `boofuzz convert` | Web 页面：粘贴原始 HTTP 报文 → 自动生成协议定义 JSON |

帮助：`boofuzz --help`。全部选项、示例文件说明、运行行为与退出码见 [CLI.md](docs/CLI.md)；JSON 协议定义写法见 [DEFINITIONS.md](docs/DEFINITIONS.md)。

## 文档导航

| 需求 | 文档 |
| --- | --- |
| CLI 全部选项、示例文件与退出码 | [CLI.md](docs/CLI.md) |
| 编写 JSON 协议、字段与读取策略 | [DEFINITIONS.md](docs/DEFINITIONS.md) |
| 用 Web 页面把 HTTP 报文转成定义 | [CONVERT.md](docs/CONVERT.md) |
| 运行本地 HTTP fuzz 靶子（httpd） | [HTTPD.md](docs/HTTPD.md) |
| 用 MoonBit 代码编写 fuzz 脚本 | [原生 MoonBit 完整示例](examples/moonbit_http/README.md)、[CODE.md](docs/CODE.md)、[可执行 API 示例](README.mbt.md)、[MODEL.md](docs/MODEL.md) |
| 配置前置路径和执行器 | [SESSION.md](docs/SESSION.md)、[RUNNER.md](docs/RUNNER.md) |
| 响应检查、故障通知和恢复回调 | [MONITORS.md](docs/MONITORS.md) |
| 理解日志、重放和退出码 | [RECORDS.md](docs/RECORDS.md)、[REPLAY.md](docs/REPLAY.md)、[REPORT.md](docs/REPORT.md) |
| 支持范围、兼容边界、验收与许可 | [UPSTREAM.md](docs/UPSTREAM.md)、[ACCEPTANCE.md](docs/ACCEPTANCE.md) |

## 许可与来源

本项目保持 **GPL-2.0-only**，见 [LICENSE](LICENSE)。移植来源、差分样本生成方式、已知差异及工具链许可注意事项见 [UPSTREAM.md](docs/UPSTREAM.md)。
