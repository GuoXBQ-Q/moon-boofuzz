# httpd：HTTP 协议 fuzz 靶子

`cmd/httpd` 是一个小的严格解析 HTTP 服务器，专门作为 fuzz 靶子设计。
与 web UI 使用的 `HttpServer`（`web/server.mbt`）不同，它对畸形输入给出
**明确的拒绝状态码**，让 fuzzer 能区分"被拒绝"和"连接被丢弃"；再配合
`--target-cmd` 的进程监视，崩溃也会被记录为 fault。

## 运行

不克隆仓库时，可直接从 mooncakes 全局安装后运行（需本机 C 编译器）：

```sh
moon install GuoXBQ-Q/moon-boofuzz/cmd/httpd
httpd --port 9000
```

在源码仓库内构建运行：

```sh
moon build --target native cmd/httpd
# 二进制位于 _build/native/debug/build/cmd/httpd/httpd.exe

_build/native/debug/build/cmd/httpd/httpd.exe --port 9000
# httpd listening on 127.0.0.1:9000
# httpd caps: max-head=8192 max-body=1048576
```

| 旗标 | 默认 | 说明 |
|---|---|---|
| `--port N` | 9000 | 绑定的回环端口；`0` = 随机空闲端口（打印实际值） |
| `--max-head N` | 8192 | 头部字节数上限，超限回 431 |
| `--max-body N` | 1048576 | body 字节数上限，超限回 413（上限 64 MiB） |
| `--lab-mode on\|off` | off | 挂载受控故障注入路由，见下文「Lab 模式」 |

绑定失败（端口被占）直接以退出码 2 结束——与 Web UI 的端口顺延策略不同，
靶子必须可寻址。

## 路由

| 请求 | 响应 |
|---|---|
| `GET /` / `HEAD /` | 200 `moon-httpd: ok` |
| `GET/POST/PUT /echo` | 200 回显请求 body（Content-Type 透传） |
| `GET /headers` / `HEAD /headers` | 200 列出解析出的全部头（小写名） |
| 其他路径 | 404 |
| 已知路径 + 不允许的方法 | 405 |

## Lab 模式（受控故障注入）

`--lab-mode on` 在常规路由之外挂载一组演练用故障路由，模拟命令注入与
缓冲区溢出两类缺陷：注入探测只回显标记字符串；超长输入越过长度阈值时
调用 C `abort()` 立即终止进程。它**不执行任何命令，也不做真正的越界
写**——崩溃是主动模拟的，进程终止即"缺陷被发现"。默认关闭，开启后
启动多打印一行 `httpd lab mode: on (loopback only)`。

这些路由仅接受 `GET`，其他方法落回常规路由（404）；头名解析不区分
大小写（`X-Lab-Data` 与 `x-lab-data` 等价）：

| 请求 | 触发条件 | 结果 |
|---|---|---|
| `GET /lab/health` | — | 200 `LAB_READY`（存活探针） |
| `GET /lab/rce/header` | `X-Lab-Command` 头含注入标记 | 命中 200 `LAB_RCE_HIT`，否则 `LAB_RCE_MISS` |
| `GET /lab/rce/path/<后缀>` | 路径后缀含注入标记 | 同上 |
| `GET /lab/bof/header` | `X-Lab-Data` 头值长度 > 64 | `abort()` 进程终止；否则 200 `LAB_BOF_SAFE` |
| `GET /lab/bof/path/<后缀>` | 路径后缀长度 > 128 | 同上 |

注入标记（按小写比较）：`;`、`|`、`$(`、`%3b`、`%7c`。

崩溃只有被进程监视器观测到才计为 failure：配合 `run --target-cmd` 时，
`abort()` 所在用例记为 `monitor_failed`（Windows 上进程退出码
-1073740791，即 0xC0000409；POSIX 上为 abort 信号），随后监视器自动
重启靶子继续跑。不带 `--target-cmd` 手动起靶子时，崩溃只表现为连接被
reset/对端关闭，不会被计为 failure。

配套示例定义：`examples/httpd_bof.json` 是一个正常 HTTP 请求（`method`
/`uri`/`X-Lab-Data` 头三个变异点），65 字节头值与 129 字节路径各越界
1 字节，7 例中 2 例 `monitor_failed`、其余 passed；`examples/httpd_lab.json`
覆盖全部四条探测路由：

```sh
moon run --target native cmd/boofuzz -- run examples/httpd_bof.json \
  --output _build/httpd-bof-demo.jsonl --combinatorial false \
  --target-cmd "_build/native/debug/build/cmd/httpd/httpd.exe --port 9000 --lab-mode on"
moon run --target native cmd/boofuzz -- report _build/httpd-bof-demo.jsonl
```

注意：`--output` 文件是追加写，重复演示前先删旧文件；崩溃后 9000 端口
会短暂处于 TIME_WAIT，紧接着重跑可能因靶子绑定失败把首个用例记成
`recovery_failed`，等半分钟即可。

## 严格解析规则（fuzz 可观察行为）

| 输入 | 结果 |
|---|---|
| 请求行不是恰好 `METHOD SP TARGET SP VERSION` | 400 |
| method 含非法 token 字符 | 400 |
| target 不以 `/` 开头且不是 `*` | 400 |
| version 不以 `HTTP/` 开头 | 400 |
| 头行缺少冒号 / 头名非法 token / 冒号前有空白 | 400 |
| Content-Length 非数字 | 400 |
| 多个 Content-Length 且值冲突 | 400（走私防护） |
| Content-Length 超过 `--max-body` | **413**（在读 body 之前就拒绝） |
| 头部终止符前超过 `--max-head` | **431** |
| 出现 `Transfer-Encoding` | **501**（不支持 chunked） |
| 无字节/停滞/对端提前断开 | 静默断连（与真实服务器一致） |

行结束符宽容（CRLF 或 LF 都接受，含裸 `\n\n` 终止符），结构严格。
每连接一请求，响应恒 `Connection: close`；写完响应后会先排空未读的
请求字节再关闭，避免 Windows 上 RST 吞掉响应。

## 用 fuzzer 打它

方式一：手动启动靶子，再跑定义：

```sh
_build/native/debug/build/cmd/httpd/httpd.exe --port 9000 &
moon run --target native cmd/boofuzz -- run examples/httpd.json \
  --output httpd-cases.jsonl --text-dump true --csv-out httpd.csv
moon run --target native cmd/boofuzz -- report httpd-cases.jsonl
```

方式二：让 CLI 孵化并监控靶子（崩溃/退出自动记录 fault 并重启）：

```sh
moon run --target native cmd/boofuzz -- run examples/httpd.json \
  --output httpd-cases.jsonl --csv-out httpd.csv \
  --target-cmd "_build/native/debug/build/cmd/httpd/httpd.exe --port 9000"
```

`examples/httpd.json` 的变异面：`method` 为 group（GET/POST/PUT/DELETE，
探测 405/404 路由分支）、`uri` 为 text 变异库（探测请求行解析）、
`X-Fuzz` 头值为 text 变异库（探测头部解析——这是其他靶子做不到的）。
结构字节（空格、CRLF、头名）全部 static，保证合法请求可到达路由层。

预期 outcome 分布：passed（200/404/405 回答）、receive_timeout /
peer_closed（静默断连类）、response_mismatch（若配置校验）、
monitor_failed（真把进程打死才算发现——默认路由打不死进程，可复现的
崩溃需要 `--lab-mode on` 的故障路由，见上文「Lab 模式」）。组合爆破默认开启后，depth-2+
的组合用例也会进入 case_limit 窗口，各分类的比例随之变化；要复现单
字段逐例枚举可加 `--combinatorial false`。

## 与 web UI 服务器的关系

`web/raw.mbt` 暴露了与 `HttpServer` 同一 C 桥（`web/http.c`）之上的
原始 socket API（`RawServer::bind/accept`、`RawConn::wait/recv/write/
close`），`cmd/httpd` 在其上实现自己的解析与路由。两者都仅绑定回环；
httpd 严格绑定端口不顺延。UI 服务器不回 400/413（静默丢弃），httpd
反之——这是设计差异，不是遗漏。

分段到达的请求会保留已接收字节；CRLF 与 LF 终止符使用各自的实际长度计算 body 起点。头部上限包含终止符，超限即返回 431。测试覆盖 LF 请求、大于初始缓冲区的 body，以及原始接收接口的 offset/capacity 边界。
