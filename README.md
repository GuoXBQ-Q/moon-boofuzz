# moon-boofuzz

MoonBit 协议模糊测试核心：定义协议、生成单字段变异、执行前置会话、通过 TCP/UDP 发送、记录结果并重放。

采用 boofuzz 固定版本 `518c13904fc32e7f2cc88c9dec934e509062953e` 的明确功能子集。核心支持 Wasm 与 Native，网络和文件 I/O 支持 Windows/Linux Native。当前源码版本为 0.1.0，尚未发布到 mooncakes。

## 开始使用

安装 [MoonBit](https://www.moonbitlang.com/download/)。Native 构建在 Windows 使用 MSVC 和 Windows SDK，在 Linux 使用 GCC/Clang。初始开发工具链为 moon 0.1.20260827、moonc v0.10.11。

```sh
git clone https://github.com/GuoXBQ-Q/moon-boofuzz.git
cd moon-boofuzz
moon update
moon check --deny-warn
moon build
moon test --deny-warn
moon build --target native
moon test --target native --deny-warn
moon run --target native cmd/boofuzz -- generate examples/offline.json --limit 3
```

全部自动验收场景使用临时文件、回环地址和临时端口，无需另启服务：

```sh
moon test --target native --deny-warn -p cmd/boofuzz
```

## CLI 流程

`examples/tcp.json`、`udp.json` 和 `stateful.json` 默认指向 127.0.0.1:9000。运行这些定义前，启动自己的测试目标并按需要修改地址和读取策略。

```sh
moon run --target native cmd/boofuzz -- run examples/tcp.json --output _build/tcp-cases.jsonl
moon run --target native cmd/boofuzz -- report _build/tcp-cases.jsonl
moon run --target native cmd/boofuzz -- replay _build/tcp-cases.jsonl --id '["packet"]/v1:packet.data:0'
```

从 report 复制实际 case_id。重放可用 `--host HOST --port PORT` 显式覆盖目标，始终发送记录中的字节，不重新生成变异。响应无需与原记录完全相同。

generate 输出 generated_case JSONL 及生成汇总；run 逐例写记录；report 按结果分类并给出失败行号和身份。每次运行使用新日志文件，避免追加相同身份后产生歧义。report 遇到损坏尾行仍输出之前的完整记录汇总，并以状态码 2 退出。replay 拒绝损坏文件；重放结果失败返回 1，配置或文件错误返回 2。

## 支持的核心

- Simple、Group、8/16/32/64 位整数、二进制 Bytes、UTF-8 字符串和分隔符变异。
- 命名嵌套块、条件块、重复、对齐、长度字段及 CRC32。
- 惰性单字段枚举、稳定身份、起始位置、数量限制与停止状态。
- DAG 会话路径；每例重新连接并执行默认前置请求，仅变异末端目标。
- TCP 完整发送与无响应/固定长度/分隔符读取；UDP 保留报文边界和空报文。
- 生命周期回调、响应检查、故障通知、恢复失败停止。
- 版本化 JSON 定义、JSONL 记录、按保存字节重放及分类报告。

旧 Static、Choice 和平面 Request 行为保留。Choice 是原项目显式候选 API，不冒充上游 Group。新 API 示例见 [README.mbt.md](README.mbt.md)，JSON 格式见 [DEFINITIONS.md](docs/DEFINITIONS.md)。

## 边界

默认单请求 1 MiB、每次执行 10,000 例、接收 64 KiB；可显式调整。超限返回明确错误或 limited 状态，不静默截断载荷。动态变异在分配前检查长度。

连接、发送和接收超时默认各 5 秒。系统主机名解析发生在套接字连接计时前；需要严格连接总时限时使用 IPv4。网络异常只表示传输/响应故障，不直接判定目标崩溃。

首版不包含 Python DSL、Web UI、TLS、IPv6、串口、原始帧、调试器、覆盖率引导、多字段组合或并行执行。String 支持动态 UTF-8 子集，不暴露上游按字符截断的 size/max_len；Bytes 填充限单字节。详细兼容边界见 [UPSTREAM.md](docs/UPSTREAM.md)。

## 验证与发布准备

[GitHub Actions](https://github.com/GuoXBQ-Q/moon-boofuzz/actions) 覆盖 Windows/MSVC、Linux、Wasm/Native 和 Linux ASan。`moon run scripts/verify.mbtx` 执行本地完整检查；GCC/Clang 下可运行 `moon run scripts/asan.mbtx`。

`moon package --list` 审查源码包内容，`moon package` 生成待发布源码包。发布前清单见 [ACCEPTANCE.md](docs/ACCEPTANCE.md)。报名申报书仍由本人撰写，本项目不代填或提交。

## 许可与来源

本项目保持 **GPL-2.0-only**，见 [LICENSE](LICENSE)。移植来源、差分样本生成方式、已知差异及工具链许可注意事项见 [UPSTREAM.md](docs/UPSTREAM.md)。本项目不是 boofuzz 官方版本。
