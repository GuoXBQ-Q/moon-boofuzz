# 进程监视器

`process/` 原生包提供目标进程生命周期控制与本地进程监视器，对齐上游
`utils/process_monitor_local.py` + `utils/debugger_thread_simple.py`
（基线 `518c13904fc32e7f2cc88c9dec934e509062953e`，GPL-2.0-only）中
不依赖调试器的部分。

## 进程控制（MoonBit API）

`Process::spawn(command)` 异步启动命令；`status()`/`alive()` 非阻塞轮询、
`wait(timeout_ms)` 带超时等待、`kill()` 终止（POSIX 用 SIGKILL，对齐上游
stop_target；Windows 为 TerminateProcess）、`pid()`/`exit_code()` 报告。
`is_windows()` 报告宿主平台——命令语义按平台分裂：Windows 把整个字符串
作为命令行交给 `CreateProcessW`（如 `cmd /c exit 3`）；POSIX 把字符串作为
shell 文本经 `/bin/sh -c` 执行（如 `exit 3`）。这与上游
DebuggerThreadSimple 的 spawn 语义一致。C 层遵循 transport/socket.c 模板：
不透明句柄、GC finalizer 释放 OS 资源、0/-1/-2 返回约定。

## ProcessMonitor

`ProcessMonitor::new(command, start_delay_ms=1000, stop_delay_ms=500)`
构造一个 `runner.Monitor`：

- `before`：目标未启动则启动（含启动延迟）；已死则透明重启
  （stop+start，对齐上游 pre_send 的 process_monitor_local.py），重启
  失败不中断用例，由后续发送暴露（摘要记入 synopsis）。
- `after`：轮询目标——**运行期内任何退出都视为故障**（包括正常退出 0，
  与上游 post_send 的存活语义一致），记入崩溃摘要并使该用例失败。
- `recover`：停止（kill + 停止延迟 + 回收）后重新启动（启动延迟 +
  存活确认）；重启失败返回 false，执行器以 `RecoveryFailed` 停止。
- `fault`：崩溃摘要保留在 `ProcessMonitor.synopsis`。

`Monitor::combine(first, second)` 链接两个监视器：before/after/fault 顺序
执行，check 与 recover 要求两者都通过——用于把进程监视器与文本输出等
用户回调配对。

## 接线

- CLI：`run --target-cmd CMD`（命令含空格时整体加引号）。
- JSON `execution`：`"target_command"`、`"target_start_delay_ms"`、
  `"target_stop_delay_ms"`；CLI 标志优先于 JSON。

## 边界

无调试器、无符号/崩溃地址分析（上游 pydbg 路径不移植）；崩溃归因是
"目标进程已退出" + 退出码。进程是本地子进程，无 pedrpc 远程监视。
C finalizer 对仍在运行的 POSIX 子进程做 best-effort SIGKILL 回收。

Source: `boofuzz/utils/process_monitor_local.py`、
`boofuzz/utils/debugger_thread_simple.py`、
`boofuzz/monitors/base_monitor.py`（钩子语义）。进程桥与
`Monitor::combine` 是 MoonBit 适配。
`process/process_wbtest.mbt`、`process/monitor_wbtest.mbt` 覆盖
spawn/退出码/kill/超时与监视器全生命周期（含恢复失败路径）。
