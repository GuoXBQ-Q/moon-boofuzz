# HTTP 报文转换器（convert 子命令）

`convert` 启动一个本地 Web 页面，把原始 HTTP 请求报文转换成协议定义 JSON，免去手写字段树的繁琐：

```sh
moon run --target native cmd/boofuzz -- convert                # 默认 http://localhost:26001/convert
moon run --target native cmd/boofuzz -- convert --ui-port 0    # 0 = 随机空闲端口
```

## 操作流程

1. **粘贴报文**：在文本框粘贴完整的原始 HTTP 请求（含头、空行和可选 body），配置目标地址（host/port）、请求名、读取策略和 case 上限，提交解析。
2. **勾选分段**：报文被拆成方法、URI、版本、每个头部值和 body，每段一个勾选框和一个**变异原语**下拉框：
   - 不勾选 = 冻结，每个用例原样重发；
   - 原语 **string library** = 内置坏字符串库（`text` 字段），URI/头部等文本段的首选；
   - 原语 **integer** = 数值边界变异（`integer` 字段，可选位宽 8/16/32/64 和端序），适合 Content-Length、端口等数字段；注意整数按二进制渲染，非 ASCII；
   - 原语 **bytes** = 二进制块变异（`bytes` 字段，可调 max_len）；
   - 原语 **random** = 随机数据（`random` 字段，可调 max_len 和用例数）；
   - 原语 **candidates** = 显式候选值（`simple` 字段 + `values_hex`），在右侧文本框每行填一个；方法段的下拉默认选它——不填候选时自动使用内置 HTTP 方法表（GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/TRACE/CONNECT/PROPFIND，剔除原值），其他段不填候选时回退到 string library。
3. **生成定义**：服务端生成 JSON 并立即用协议解析器自校验，展示用例总数、前 3 个实际载荷（ASCII + hex），JSON 可复制或下载。报文与选项通过隐藏字段随表单传递，服务端不保存任何状态。

报文解析失败、选项非法或原语参数非法（如整数位宽不是 8/16/32/64）时返回 400 页面并给出原因，不会生成半成品定义。

## 分段 → 字段类型映射

| 所选原语 | 生成的字段类型 | 参数 |
| --- | --- | --- |
| string library | `text`（fuzzable: true，坏字符串库） | — |
| integer | `integer`（数值边界变异，二进制渲染） | 位宽（8/16/32/64）、端序 |
| bytes | `bytes`（二进制块变异） | max_len |
| random | `random`（随机数据） | max_len、用例数 |
| candidates | `simple` + `values_hex` | 候选文本框 |
| （未勾选） | `text`（fuzzable: false，冻结原样） | — |

无论选哪种原语，空格、CRLF、头部名前缀、头结束空行等结构字节都是 `static` 字段，不参与变异。

生成的 execution 固定为 `transport: tcp`，读取策略三选一：

- `until`（默认）：读到 `0d0a0d0a`（CRLFCRLF），正好捕获 HTTP 响应头；
- `none`：发送后不等待响应；
- `fixed`：读取固定字节数（表单中的 Fixed length）。

## 保真与限制

- **逐字节还原**：所有冻结字段渲染出的报文与粘贴内容逐字节一致，包括冒号后空格的有无和 CRLF/LF 行尾。方法、URI 等位置按线上顺序拆分，结构字节成为独立的 `static` 字段。选择 string library 或 candidates 原语同样保持文本形态；选择 integer/bytes/random 后该段按二进制渲染（上游原语行为），与原报文的逐字节一致不再成立。
- **仅支持 HTTP 请求**：fuzz HTTP 响应需要 TCP 服务端模式（未移植）。请求行必须是 `方法 SP URI SP HTTP版本` 三段；头部行必须含冒号。
- **body 是 UTF-8 文本**：二进制 body 请手工编辑生成的 JSON（`bytes` 字段）。
- **Content-Length 提示**：报文声明了 Content-Length 时，勾选 body 段会显示长度不匹配提醒——候选值改变 body 长度而该头部保持冻结，多数服务器会挂起或断连。经典做法是把 Content-Length 值本身作为头部值段的显式候选（如 `0`、`-1`、超大值）。
- **混合行尾**：CRLF 与裸 LF 混用的报文按消息级行尾归一（有 `\r` 按 CRLF 处理）；头终结符与 body 始终保持原字节。
- 输入上限 64 KiB；生成的定义同样受单请求 1 MiB、单次执行 10,000 例等全局上限约束（见 README「边界」）。

## 命令行衔接

```sh
# 下载或复制 JSON 保存为 my-http.json 后：
moon run --target native cmd/boofuzz -- generate my-http.json --limit 5   # 离线检查变异载荷
moon run --target native cmd/boofuzz -- run my-http.json --output _build/http-cases.jsonl
moon run --target native cmd/boofuzz -- report _build/http-cases.jsonl
```

[examples/http.json](../examples/http.json) 是转换器对一条 GET 报文的输出样例（URI 段勾选自动变异，其余冻结），可直接 `generate`/`run`。
