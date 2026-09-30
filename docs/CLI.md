# CLI 命令与选项

所有命令从项目根目录执行。查看帮助：`moon run --target native cmd/boofuzz -- --help`。

## 命令与选项

| 命令 | 输入与用途 | 主要选项 |
| --- | --- | --- |
| `generate` | JSON 协议定义 → 变异载荷 JSONL，不连接目标 | `--limit N`、`--start N`、`--id ID`（需 `--combinatorial false`）、`--combinatorial true|false`、`--max-depth N`（组合深度上限）；组合爆破默认开启（与上游 CLI 一致） |
| `run` | JSON 协议定义 → 逐例执行并保存实际流量 | 必填 `--output FILE`；可选 `--limit N`（缺省**无上限**，跑完为止）、`--combinatorial true|false`、`--max-depth N`、`--start N`、`--end N`、`--sleep-between-ms N`（用例间隔）、`--text-dump true|false`（逐例实时日志）、`--db FILE`（缺省自动写 `boofuzz-results/run-<UTC时间戳>.db`，与上游一致常开）、`--record-passes N`、`--csv-out FILE`、`--web-port N`（缺省 26000，与上游一致常开；`0` 为随机空闲端口）、`--target-cmd CMD` |
| `open` | 结果库/JSONL → 本地只读 Web 视图 | `--ui-port N`（默认 26000） |
| `convert` | Web 页面：粘贴原始 HTTP 报文 → 勾选分段并选择变异原语（字符串库/整数/二进制/随机/候选值）→ 自动生成协议定义 JSON（校验、用例数、载荷预览、复制/下载） | `--ui-port N`（默认 26001） |
| `report` | JSONL 执行记录 → 分类计数、失败身份和行号 | `--max-bytes N` |
| `replay` | JSONL 执行记录 → 按身份重放保存的字节 | 必填 `--id ID`，可选成对的 `--host HOST --port PORT`、`--max-bytes N` |

## 运行行为

与上游一致，`run` 每次都会在 `boofuzz-results/` 下生成一份 SQLite 结果库（`run-<UTC时间戳>.db`），并在默认端口 26000 启动实时 Web UI（端口被占时自动顺延）；进程在输出摘要后退出，不等待交互。组合爆破默认开启，按 id 续跑需显式 `--combinatorial false`。

从 report 复制实际 case_id；重放可用 `--host HOST --port PORT` 显式覆盖目标，始终发送记录中的字节，不重新生成变异，响应无需与原记录完全相同。

generate 输出 generated_case JSONL 及生成汇总；run 逐例写记录；report 按结果分类并给出失败行号和身份。每次运行使用新日志文件，避免追加相同身份后产生歧义。`limited` 表示达到配置的数量上限，并不表示一定还有未生成的用例。生成结果与执行记录是两种不同格式，`replay` 的输入应来自 `run --output`。

退出码语义（`run` 成功写完记录即返回 0、即使其中存在失败用例，判断目标结果应查看 `report`；report 遇到损坏尾行仍输出之前的完整汇总并以状态码 2 退出；replay 重放结果失败返回 1，配置或文件错误返回 2）见 [REPORT.md](REPORT.md) 的退出码表。

## 示例文件

`examples/tcp.json`、`udp.json` 和 `stateful.json` 默认指向 127.0.0.1:9000；前两者需要兼容的测试目标，`stateful.json` 可配合仓库自带的 `cmd/stateful_target` 直接运行，详见 [STATEFUL.md](STATEFUL.md)。

- [offline.json](../examples/offline.json)：保留 `PING ` 前缀，依次生成空值、`00ff` 二进制值和 `long`。`payload_hex` 是完整请求，`prefix_hex` 是会话前置请求。
- [tcp.json](../examples/tcp.json)：向 127.0.0.1:9000 发送 `00ff`、`414141` 两个用例，每例等待 2 字节响应，接收超时 100 ms。目标不回复时会记录超时。
- [udp.json](../examples/udp.json)：发送空报文及 `00ff`，每例接收一个 UDP 报文。
- [stateful.json](../examples/stateful.json)：每个新连接重新发送 `HELLO`、`AUTH test`，再发送变异 `DATA`；只变异末端 `query`，每步等待响应。可直接运行 [STATEFUL.md](STATEFUL.md) 中的本地靶子和命令。
- [http.json](../examples/http.json)：变异 HTTP 请求行（URI），可指向任意 HTTP 服务，或配合 [HTTPD.md](HTTPD.md) 的自带 httpd 靶子。
- [httpd.json](../examples/httpd.json)、[httpd_lab.json](../examples/httpd_lab.json)：面向自带 httpd 靶子的动词组变异与实验室场景（拒绝状态码、崩溃注入），见 [HTTPD.md](HTTPD.md)。
- [httpd_bof.json](../examples/httpd_bof.json)：正常 HTTP 请求打 lab 故障路由的崩溃演示（65 字节头值/129 字节路径各越界 1 字节即触发 `monitor_failed`），见 [HTTPD.md](HTTPD.md) 的 Lab 模式。
- [http_get_full.json](../examples/http_get_full.json)：头部丰富的完整 GET 请求，变异点覆盖方法（GET/HEAD）、URI 显式候选和字符串库头部；[http_post_full.json](../examples/http_post_full.json)：完整 POST 请求，变异点覆盖方法（POST/PUT）、Content-Length 显式候选和字符串库 body。两者各有等价的 MoonBit API 版本 `examples/http_get_full`、`examples/http_post_full`，支持离线生成与在线执行两种模式。

## 定义要点

`value_hex` 定义正常值，`values_hex` 定义显式变异候选；默认值用于普通渲染和前置请求，不会自动额外插入变异序列。Group 会从候选中只移除一次默认值。自动变异可使用 `integer`、`bytes` 或 `text` 字段。

运行前应按协议配置响应边界：TCP 用 `none`、`fixed` 或 `until`，UDP 用 `none` 或 `datagram`。完整 JSON 写法见 [DEFINITIONS.md](DEFINITIONS.md)。
