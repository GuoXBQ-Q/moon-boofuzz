# moon-boofuzz

MoonBit 协议模糊测试核心：定义协议、生成单字段变异、执行前置会话、通过 TCP/UDP 发送、记录结果并重放。

采用 boofuzz 固定版本 `518c13904fc32e7f2cc88c9dec934e509062953e` 的明确功能子集；核心支持 Wasm 与 Native，网络和文件 I/O 支持 Windows/Linux Native。已发布到 [mooncakes.io](https://mooncakes.io/docs/GuoXBQ-Q/moon-boofuzz)（页面显示最新版本）；支持范围与兼容边界见 [UPSTREAM.md](docs/UPSTREAM.md)。

## 前置环境

- 安装 [MoonBit](https://www.moonbitlang.com/download/)。纯逻辑核心（协议模型与变异枚举）在 Wasm 下即可使用，无需 C 环境。
- 网络与文件 I/O 仅支持 Native，需要系统 C 编译器：Windows 推荐 [llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases)（把 bin 加入 PATH）或 Visual Studio MSVC，Linux 使用 GCC。当前验证工具链为 moon 0.1.20260920、moonc v0.10.14。

## 安装

作为库使用：在自己的模块中执行 `moon add GuoXBQ-Q/moon-boofuzz`，然后在包的 `moon.pkg` 里 import `"GuoXBQ-Q/moon-boofuzz"`。

从源码运行完整 CLI：

```sh
git clone https://github.com/GuoXBQ-Q/moon-boofuzz.git
cd moon-boofuzz
moon update
moon check --deny-warn
moon build --target native
moon test --target native --deny-warn
```

运行 `moon update` 是为独立开发脚本初始化包索引，正常使用 CLI 不需要 Python。

## 使用示例

库示例由 `moon test` 执行。根包测试使用 `@moon_boofuzz` 别名；在自己的项目中按所用别名导入即可。`CompiledRequest` 用于新协议模型：正常渲染和变异枚举分别调用 `render()` 与 `cases()`，用 `next()` 逐个获取载荷，避免先建立完整用例数组。

```mbt check
///|
test "named request quick start" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("packet", [
      Leaf("prefix", @moon_boofuzz.Field::simple(b"PING ", [])),
      Leaf("value", @moon_boofuzz.Field::simple(b"ok", [b"", b"\x00\xff"])),
    ]),
  )
  assert_eq(request.render(), b"PING ok")
  let cases = request.cases(limit=1)
  assert_eq(cases.next().map(case => case.payload), Some(b"PING "))
  assert_eq(cases.next(), None)
  assert_eq(cases.state(), Limited)
  let resumed = request.cases(start=cases.position())
  assert_eq(resumed.next().map(case => case.payload), Some(b"PING \x00\xff"))
}
```

字段路径包含请求名，例如 `packet.value`。字段原语与模型细节见 [MODEL.md](docs/MODEL.md)；会话图、网络执行及回调见 [SESSION.md](docs/SESSION.md)、[RUNNER.md](docs/RUNNER.md) 与 [MONITORS.md](docs/MONITORS.md)。

CLI 侧先跑自动验收场景（临时文件、回环地址和临时端口，无需另启服务），再离线生成用例看产出，最后连接自己的服务：

```sh
moon test --target native --deny-warn -p cmd/boofuzz
moon run --target native cmd/boofuzz -- generate examples/offline.json --limit 3
moon run --target native cmd/boofuzz -- run examples/tcp.json --output _build/tcp-cases.jsonl
moon run --target native cmd/boofuzz -- report _build/tcp-cases.jsonl
moon run --target native cmd/boofuzz -- replay _build/tcp-cases.jsonl --id '["packet"]/v1:packet.data:0'
```

## CLI 流程

| 命令 | 用途 |
| --- | --- |
| `generate` | JSON 协议定义 → 变异载荷 JSONL，不连接目标 |
| `run` | JSON 协议定义 → 逐例执行并保存实际流量 |
| `open` | 结果库/JSONL → 本地只读 Web 视图 |
| `convert` | Web 页面：粘贴 HTTP 报文 → 自动生成协议定义 JSON |
| `report` | JSONL 执行记录 → 分类计数、失败身份和行号 |
| `replay` | JSONL 执行记录 → 按身份重放保存的字节 |

帮助：`moon run --target native cmd/boofuzz -- --help`，所有命令从项目根目录执行。全部选项、示例文件说明、运行行为与退出码见 [CLI.md](docs/CLI.md)；JSON 协议定义写法见 [DEFINITIONS.md](docs/DEFINITIONS.md)。

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
