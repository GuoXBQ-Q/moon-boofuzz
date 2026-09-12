# Replay and report commands

## 常用命令

以下命令在项目根目录执行；日志应来自 `run --output`，而非 `generate` 的标准输出。

```sh
moon run --target native cmd/boofuzz -- report _build/run-001.jsonl
moon run --target native cmd/boofuzz -- replay _build/run-001.jsonl --id '["packet"]/v1:packet.data:0'
moon run --target native cmd/boofuzz -- replay _build/run-001.jsonl --id '["packet"]/v1:packet.data:0' --host 127.0.0.1 --port 9001
```

将示例身份替换为报告中的实际 `case_id`。报告的 `failures[].line` 是日志行号，`failed_step` 从 0 开始，-1 表示连接阶段失败。回调故障不一定对应具体请求步骤。

| 命令结果 | 退出码 |
| --- | --- |
| generate 正常结束或达到数量上限 | 0 |
| run 完成执行和记录，包括记录了失败用例 | 0 |
| report 成功解析整个文件 | 0 |
| replay 执行成功 | 0 |
| replay 出现网络或响应失败 | 1 |
| 参数/配置/文件错误，或 report 遇到损坏行 | 2 |

`run` 返回 0 不代表目标通过了所有用例。请用报告的 `outcomes` 和 `failures` 判断结果。重放沿用读取边界和超时，但不比较新旧响应内容，也不重跑原监控回调。

`report CASES.jsonl` summarizes total cases and counts by outcome, with failure
case IDs, line numbers and steps. It prints a report for the complete prefix
even if a later line is corrupt, includes the issue, and exits with code 2.
`--max-bytes N` raises the default 64 MiB file-read limit explicitly.

`replay CASES.jsonl --id CASE_ID` validates the complete file, selects an
unambiguous identity, and replays saved bytes. Add `--host HOST --port PORT`
together to override the target. The JSON result includes actual sent/received
hex, outcome and failed step. Exit 0 means successful replay execution, 1 means
a replay network/response failure, and 2 means a configuration or file error.
Existing monitor callbacks and response equality checks are not rerun.

The CLI scenarios test offline parser inputs, TCP timeout recording/reporting/
replay after deleting the source definition, and fresh handshake/authentication
for every stateful target case. Reports are new GPL-2.0-only functionality over
the project's portable record schema, not an upstream database reader.
