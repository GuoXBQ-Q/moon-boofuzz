# boofuzz 移植补齐计划（已完成）

目标：把 moon-boofuzz 从"明确功能子集"补齐到对 boofuzz 0.4.2
（基线 `518c13904fc32e7f2cc88c9dec934e509062953e`）的更完整移植。
本文档跟踪八阶段计划的进度；已完成项见 `ROADMAP.md` 功能清单
（第 1–52 行）与 git 历史。

纪律（贯穿所有阶段）：完全对齐上游行为（含 quirk，附上游 `文件:行号`
引用）；差分测试用 `scripts/oracle.mbtx` 以 Python 为开发 oracle；
每个功能 = 实现 + wbtest/test 双层测试 + docs 文档（含 Source 段）+
`UPSTREAM.md` 表行 + `ROADMAP.md` 行；核心包保持 Wasm 兼容、无网络、
无新模块依赖；每阶段验收 = `moon run scripts/verify.mbtx` 全绿。

## 进度总览

| 阶段 | 内容 | 状态 | 提交 |
| --- | --- | --- | --- |
| 0 | 基础重构（多点替换 / 边界抽函数 / MT19937） | ✅ 完成 | c11b0bc 内 |
| 1 | 变异核心补齐（Size/Checksum 自动变异、条件运算符、隐藏用例发射、fuzz_values、Group 笛卡尔、RandomData/Float/FromFile/Mirror） | ✅ 完成 | c11b0bc |
| 2 | 组合爆破、会话变量、Repeat 动态、边回调 | ✅ 完成 | c11b0bc、5d65b05 |
| 3 | 执行器鲁棒性八项（errno 分类、开关、重试、崩溃阈值、续跑、按 id 重生成、实时日志、步进） | ✅ 完成 | 47daaf6、88ad3e5 |
| 4 | 进程监视器（process/ 原生包 + ProcessMonitor + --target-cmd） | ✅ 完成 | f896b68 |
| 5a | 校验和算法集（crc32c/adler32/md5/sha1 + ipv4/udp 函数） | ✅ 完成 | 631c5b7 |
| 5b-1 | IPv6 双栈传输 | ✅ 完成 | 9212c6d |
| 5b-2 | File 传输 | ✅ 完成 | 074fcf7 |
| 6a | CSV 导出（--csv-out） | ✅ 完成 | d3e479a |
| 6b | SQLite 层 | ✅ 完成 | b7c9d94 |
| 6c | Web UI + open 子命令 | ✅ 完成 | e455043 |
| 6d | --record-passes 写入节流 | ✅ 完成 | b7c9d94 |
| 5c | 传输长尾（UDP server/广播完成；Unix/Serial/Raw 评估为永久边界） | ✅ 完成 | 017cd0e |
| 7 | 收尾（来源表/README/ACCEPTANCE/ASan/包审查；推送核对待维护者） | ✅ 基本完成 | 本次提交 |

当前验证基线：Wasm 100 / Native 173 测试全绿，`verify.mbtx` 通过，
ASan 零报告。

## 剩余工作明细

### 阶段 6b：SQLite 层（规模：大）✅ 完成

- [x] vendor sqlite3 amalgamation（公有领域，GPL-2 兼容）到 `db/sqlite3.c`
  并在 `db/moon.pkg` 声明 native-stub；注册 `verify.mbtx` 接口快照与
  `asan.mbtx` 列表（SQLite 3.45.3 未修改副本，与上游 CI 产物同版本）
- [x] 最小 C 绑定：open/exec/prepare/step/column/close，句柄 finalizer
  遵循 socket.c 模板（0/-1/-2 约定；-2 = 有行可读）
- [x] 表结构对齐上游 `cases(name,number,timestamp)` /
  `steps(test_case_index,type,description,data,timestamp,is_truncated)`
  （fuzz_logger_db.py:46-50），流量 512 字节截断
- [x] 写入端：`run --db FILE` 双写 JSONL + SQLite（与 6d 的
  keep-only-n 节流共用逻辑）
- [x] 读取端：FuzzLoggerDbReader 等价（query / failure_map），供 open 与
  Web UI 使用
- [x] 测试：临时库往返、失败映射、512 截断 + 上游真实产物
  fixtures/db/oracle-run.db 读取差分

### 阶段 6c：Web UI + open 子命令（规模：大）✅ 完成

- [x] 手写最小 HTTP/1.1 服务（web/http.c，socket.c 模板，无新依赖）：
  listen/accept/解析 GET/返回文本
- [x] 路由对齐上游 web/app.py：`/`（进度条 + 崩溃列表）、
  `/test-case/<id>`、`/api/current-run`、`/api/test-case/<index>`、
  `/api/current-test-case`、`/togglepause`
- [x] pause 标志与用例循环联动（每例前 WebUi::gate 服务请求并在暂停期
  保持服务）
- [x] 端口占用自动 +1（session.py build_webapp_thread 语义）
- [x] `moon-boofuzz open FILE`：离线打开结果库/JSONL 起本地查看服务
  （等价 `boofuzz open`，session_info.py 只读视图）
- [x] 页面为轻量手写 HTML/CSS/JS（对应 Flask 模板的最小子集，内联）
- [x] 测试：socket 层 HTTP 回环 wbtest（/api/current-run 断言 JSON、
  302、404、端口 +1、OfflineSession 双后端、LiveSession observe/gate）、
  CLI `run --web-port` 端到端

### 阶段 6d：--record-passes N（规模：小）✅ 完成

- [x] 通过用例进内存环形缓冲（最多 N 条），失败用例立即写 + 回填缓冲
  （等价 `fuzz_db_keep_only_n_pass_cases`，fuzz_logger_db.py:206-225；
  JSONL 侧 `recordio/ThrottledWriter`，SQLite 侧 `num_log_cases`）
- [x] JSONL capture 路径加节流包装；默认全写（N=0 表示不节流）
- [x] CLI `--record-passes N`；测试：3 通过 + 1 失败 → 文件含失败 + 前 N
  条通过（throttle_wbtest.mbt）+ CLI 端到端（cli_wbtest.mbt）

### 阶段 5c：传输长尾（规模：中-大，可按项独立交付）

- [x] UDP server 模式（bind + recvfrom 记录对端 + sendto 回发，对齐
  udp_socket_connection.py:36-133；Runner 每例先预接收等待目标请求，
  超时记 receive_timeout）
- [x] UDP 广播（SO_BROADCAST + 非连接 sendto；JSON
  `"udp_broadcast": true`）
- [ ] Unix socket——**评估结论：不移植**。Windows 端 llvm-mingw 的
  winsock2 头未声明 AF_UNIX（AFIX 路径仅在部分 SDK/Win10+ 可用且仅限
  客户端语义），双平台 CI 无法统一构建与测试；与 pedrpc 同列永久边界
- [ ] Serial——**评估结论：不移植**。pyserial 路径需要 termios /
  Win32 COM 两套底层 + message_separator_time / content_checker 状态机
  与硬件相关的行为，无法离线确定性测试；见"永久边界"
- [ ] Raw L2/L3——**评估结论：不移植**。AF_PACKET 为 Linux 专有，
  moon.pkg 无按 OS 的目标门控，纳入将破坏 Windows 构建；见"永久边界"

### 阶段 7：收尾（规模：中）

- [x] `UPSTREAM.md` 来源表终核（对照全部 docs/ 的 Source 段）：DB/WEB/
  UDP server-broadcast/CSV/节流均有表行；BINARY/TEXT 补正式 Source 段；
  RECORDS.md 增补 CSV 与结果库说明并移除过时的"无 SQLite 依赖"表述
- [x] `README.md` 边界节重写（已补齐能力移出"不包含"清单；仍不含
  DSL/TLS/串口/Unix socket/Raw/多播等），CLI 表补 `--db`/
  `--record-passes`/`--web-port`/`open`
- [x] `ACCEPTANCE.md` 表述与功能提交数对齐（ROADMAP 第 1–52 行），ASan
  范围与各阶段测试描述更新
- [x] ASan：`scripts/asan.mbtx` 覆盖 transport/recordio/process/db/
  web/cmd（llvm-mingw 实测零 AddressSanitizer 报告；注入先行修复依赖方
  测试可执行文件的链接）
- [x] 推送后确认 GitHub Actions 双平台全绿（Windows MSVC / Linux +
  Wasm/Native，run ed93693）；Windows 端定位并修复 process 包 ECHILD
  语义、socket.c 缺失 stdlib.h 导致的 MSVC int 截断 malloc（0xc0000005
  根因），并补 ASan 锚点与崩溃诊断器
- [x] `moon package --list` 审查源码包内容：源码/测试/LICENSE/文档/
  fixtures 齐全；`boofuzz-results` 历史 .db 样本已从仓库删除（无引用，
  读取差分夹具由 `fixtures/db/oracle-run.db` 承担）；`scripts/*.mbtx`
  开发工具保留在仓库但经 `.gitignore` 排除出源码包（moon 打包遵循
  .gitignore）

## 永久边界（文档化，不移植）

pedrpc RPC 框架（监视器走进程内 Monitor）、pydbg 调试器与
crash_binning、curses TUI（上游也不支持 Windows）、vmcontrol、
scada/DNP3、NETCONF、TLS、pgraph 图渲染（GML/Graphviz）、Python `s_*`
DSL（JSON/MoonBit API 为一等接口）、协议模板全集（legos）、Unix 域
socket（Windows 工具链无 AF_UNIX 头，双平台 CI 无法统一）、Serial 串口
（termios/Win32 COM 硬件相关，无法离线确定性测试）、Raw L2/L3
（AF_PACKET 仅 Linux，moon.pkg 无按 OS 门控）。

## 已知行为差异（有意保留，均有文档）

- `num_mutations` 对禁用字段计 0（上游可能仍计数）——UPSTREAM.md
- 条件隐藏块发射空载荷用例后已对齐上游；ordinal 无空洞
- UDP 载荷超限拒绝而非截断——UDP.md
- Web UI 默认关闭（`run --web-port` 显式启用），上游默认 26000 常开；
  服务在用例间隙而非独立线程——WEB.md
- RandomData 的计数怪癖（fuzz_values 计入随机条数）未复现——PRIMITIVES.md
- Float `num_mutations` 等于实际产出数（上游虚报 max_mutations）
- 上游 Repeat(variable=) docstring 声称禁用 fuzzing 但实现未禁用，本移植
  保留实现行为——VARIABLES.md
- SQLite 步骤按 JSONL 记录重放：每步固定成对记录 send/receive（上游按
  会话实际事件逐条记录），失败由 outcome 行表达——DB.md
- 拨号重试放弃时记录失败用例后停止（上游直接抛出，不产出该用例记录）；
  `run --start/--end` 为 0 基全局序号（上游 index_start/index_end 为 1 基）
  ——RUNNER.md
- 元素级故障阈值不豁免 Group/Repeat 元素（上游对二者不触发元素耗尽）；
  监视器回调异常记录为 CallbackFailed 但不计阈值、不触发恢复（上游记
  log_error 后继续传输），`after` 抛 `MonitorSignal::TargetFailed` 的
  监视器故障信号例外——按上游 post_send→log_fail 以 `MonitorFailed`
  计入失败并触发恢复；接收超时、对端关闭与被忽略的连接重置同样
  只记录不计故障，check_data_received 可将空读取升级为 NothingReceived
  ——RUNNER.md、MONITORS.md、PROCESS.md
- `--csv-out` 为独立的每用例一行导出格式，非上游 fuzz_logger_csv.py 的
  逐消息行格式；上游 receive 行截断 quirk（"recv"/"receive" 不匹配）逐字
  保留——RECORDS.md、DB.md
- 组合爆破在嵌套结构 depth≥2 时少于上游（上游按顶层条目过滤 skip，
  会额外发射载荷重复的跨顺序用例）；扁平请求逐例一致——MUTATION.md
