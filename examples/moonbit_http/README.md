# 用 MoonBit 代码定义 HTTP fuzz 报文

[main.mbt](main.mbt) 是完整可运行的示例：协议结构、默认值和变异候选全部写在 MoonBit 中，不读取 JSON 定义。它使用根包的 `CompiledRequest` / `Field`，并通过 `Runner` 执行网络测试。

需要 MoonBit 与 Native C 编译器。在项目根目录先离线查看前 8 个载荷：

```sh
moon run --target native examples/moonbit_http
```

输出包含正常报文和每个用例的 **十六进制完整报文**，因此 `00ff` 等二进制变异不会被 UTF-8 文本显示掩盖。

| 字段路径 | 定义方式 | 行为 |
| --- | --- | --- |
| `http_request.method` | `Field::group([GET, POST, PUT])` | 默认 GET；POST、PUT 是候选 |
| `http_request.path` | `Field::simple(/echo, [/, /headers, /missing])` | 仅使用显式候选 |
| `http_request.headers.value` | `Field::simple(seed, [空、00ff、AAAA])` | 变异 `X-Fuzz` 头的值 |
| 空格、HTTP 版本、Host、头名和 CRLF | `Field::simple(..., [], fuzzable=false)` | 每例保持不变 |

三个变异点各自产生 2、3、3 个用例，默认按单字段顺序共 8 例。用 `Nested(Block::new("headers", ...))` 表示头部；改动字段列表即可选择自己的变异面。例如将 `Field::simple` 换成 `Field::text`，可使用内置坏字符串语料。

要实际向本地靶子发包，在**另一个终端**先启动仓库提供的 HTTP 靶子：

```sh
moon run --target native cmd/httpd -- --port 9000
```

然后在项目根目录执行：

```sh
moon run --target native examples/moonbit_http -- run 127.0.0.1 9000
```

`Runner` 每例新建 TCP 连接，发送代码构建的报文，读取到 HTTP 响应头结束，并打印用例字段与结果。示例限制为 8 例；目标无法连接时最多重试一次。这里的 `passed` 表示发送/读取流程成功，不代表 HTTP 状态码一定是 200，也不等同于目标没有缺陷。

更完整的原语、前置会话和监视器用法见 [CODE.md](../../docs/CODE.md)；[cmd/httpfuzz](../../cmd/httpfuzz/main.mbt) 是另一个使用内置字符串变异库的程序示例。
