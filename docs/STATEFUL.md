# 多报文会话的 JSON 手工测试

[examples/stateful.json](../examples/stateful.json) 定义一条 `hello → auth → query` 路径。每个 fuzz 用例新建一条 TCP 连接，在同一连接上先发送默认的 `HELLO\n`、`AUTH test\n`，最后发送一次变异后的 `DATA …\n`。两例的最后一步分别是 `DATA one\n` 与 `DATA two\n`。

JSON 中，`requests` 定义每个完整报文及字段；`edges` 定义前后依赖；`targets: ["query"]` 只选择 query 作为变异目标，因此 hello/auth 不产生自己的 fuzz 用例。`value_hex` 是正常值，`values_hex` 是变异候选，`0a` 是换行字节。每个请求名在 `execution.policies` 中对应一个读取规则：`until` 等待响应中的换行；若不配置，默认发完该步就继续，不会等前置步骤的响应。

在项目根目录打开两个 PowerShell 终端。终端一启动本机测试靶子（先退出占用 9000 端口的其他服务）：

```powershell
moon run --target native cmd/stateful_target
```

看到 `stateful target listening on 127.0.0.1:9000` 后保持终端开启。终端二先离线核对生成结果，再执行 fuzz：

```powershell
moon run --target native cmd/boofuzz -- generate examples/stateful.json --limit 2
moon run --target native cmd/boofuzz -- run examples/stateful.json --output _build/stateful-manual.jsonl --limit 2 --text-dump true
moon run --target native cmd/boofuzz -- report _build/stateful-manual.jsonl
```

`generate` 的每行 `prefix_hex` 应相同（HELLO、AUTH test），`payload_hex` 应分别是 DATA one、DATA two。靶子终端应按顺序打印六条收到的报文：`HELLO → AUTH test → DATA one`，再 `HELLO → AUTH test → DATA two`。结果文件每个用例有三个 `steps`，各含 `sent_hex`、`received_hex`；`report` 预期显示两个 passed。查看持久化页面可运行：

```powershell
moon run --target native cmd/boofuzz -- open _build/stateful-manual.jsonl
```

如需测试自己的协议，替换请求字段字节、图边、目标名和 endpoint，并让 `policies` 匹配各步实际响应边界。这个靶子仅实现示例的行协议；`cmd/httpd` 每连接只处理一条 HTTP 请求，不能用于验证这组三步报文。`passed` 表示发送和按规则读取成功，不代表应用响应符合业务预期；请检查每步 `received_hex`，或配置响应检查。
