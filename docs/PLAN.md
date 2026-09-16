# boofuzz 移植补齐计划（进行中）

目标：把 moon-boofuzz 从"明确功能子集"补齐到对 boofuzz 0.4.2
（基线 `518c13904fc32e7f2cc88c9dec934e509062953e`）的更完整移植。
本文档跟踪八阶段计划的进度；已完成项见 `ROADMAP.md` 功能清单
（第 1–46 行）与 git 历史。

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
| 6b | SQLite 层 | ⬜ 未开始 | — |
| 6c | Web UI + open 子命令 | ⬜ 未开始 | — |
| 6d | --record-passes 写入节流 | ⬜ 未开始 | — |
| 5c | 传输长尾（Unix/Serial/Raw L2/L3/UDP 广播与 server） | ⬜ 未开始 | — |
| 7 | 收尾 | ⬜ 未开始 | — |

当前验证基线：Wasm 99 / Native 137 测试全绿，`verify.mbtx` 通过。

## 剩余工作明细

### 阶段 6b：SQLite 层（规模：大）

- [ ] vendor sqlite3 amalgamation（公有领域，GPL-2 兼容）到 `db/sqlite3.c`
  并在 `db/moon.pkg` 声明 native-stub；注册 `verify.mbtx` 接口快照与
  `asan.mbtx` 列表
- [ ] 最小 C 绑定：open/exec/prepare/step/column/close，句柄 finalizer
  遵循 socket.c 模板（0/-1/-2 约定）
- [ ] 表结构对齐上游 `cases(name,number,timestamp)` /
  `steps(test_case_index,type,description,data,timestamp,is_truncated)`
  （fuzz_logger_db.py:46-50），流量 512 字节截断
- [ ] 写入端：`run --db FILE` 双写 JSONL + SQLite（与 6d 的
  keep-only-n 节流共用逻辑）
- [ ] 读取端：FuzzLoggerDbReader 等价（query / failure_map），供 open 与
  Web UI 使用
- [ ] 测试：临时库往返、失败映射、512 截断

### 阶段 6c：Web UI + open 子命令（规模：大）

- [ ] 基于 transport socket C 层手写最小 HTTP/1.1 服务（无新依赖）：
  listen/accept/解析 GET/返回静态文本
- [ ] 路由对齐上游 web/app.py：`/`（进度条 + 崩溃列表）、
  `/test-case/<id>`、`/api/current-run`、`/api/test-case/<index>`、
  `/togglepause`
- [ ] pause 原子标志与 Runner::next 联动（每例前检查）
- [ ] 端口占用自动 +1（对齐上游行为）
- [ ] `moon-boofuzz open FILE`：离线打开结果库/JSONL 起本地查看服务
  （等价 `boofuzz open`，session_info.py 只读视图）
- [ ] 页面为轻量手写 HTML/JS（对应 Flask 模板的最小子集）
- [ ] 测试：socket 层 HTTP 回环 wbtest（请求 /api/current-run 断言 JSON）

### 阶段 6d：--record-passes N（规模：小）

- [ ] 通过用例进内存环形缓冲（最多 N 条），失败用例立即写 + 回填缓冲
  （等价 `fuzz_db_keep_only_n_pass_cases`，fuzz_logger_db.py:206-225）
- [ ] JSONL capture 路径加节流包装；默认全写（N=0 表示不节流）
- [ ] CLI `--record-passes N`；测试：3 通过 + 1 失败 → 文件含失败 + 前 N
  条通过

### 阶段 5c：传输长尾（规模：中-大，可按项独立交付）

- [ ] Unix socket（AF_UNIX 路径连接；Windows AF_UNIX 可用性需评估，
  errno 处理同 TCP）
- [ ] UDP 广播（SO_BROADCAST + sendto 路径——当前 connected-socket
  架构需要扩展非连接发送）
- [ ] UDP server 模式（recvfrom 记录对端 + 回发，对齐
  udp_socket_connection.py:67-133）
- [ ] Serial（Win32 COM / termios；`message_separator_time`、
  `content_checker`、leftover bytes，对齐 serial_connection*.py）
- [ ] Raw L2/L3（Linux AF_PACKET；确认 moon.pkg 平台约束能力）
- [ ] 每项独立提交：C 桥 + wbtest + docs + ROADMAP 行

### 阶段 7：收尾（规模：中）

- [ ] `UPSTREAM.md` 来源表终核（对照全部 docs/ 的 Source 段）
- [ ] `README.md` 边界节重写（已补齐的能力移出"首版不包含"清单）
- [ ] `ACCEPTANCE.md` 表述与功能提交数对齐（ROADMAP 1–N 行）
- [ ] ASan：`scripts/asan.mbtx` 跑 process/ 与 db/（gcc/clang 环境）
- [ ] 推送后确认 GitHub Actions 双平台（Windows MSVC / Linux）+ Wasm 与
  Native 全绿
- [ ] `moon package --list` 审查源码包内容

## 永久边界（文档化，不移植）

pedrpc RPC 框架（监视器走进程内 Monitor）、pydbg 调试器与
crash_binning、curses TUI（上游也不支持 Windows）、vmcontrol、
scada/DNP3、NETCONF、TLS、pgraph 图渲染（GML/Graphviz）、Python `s_*`
DSL（JSON/MoonBit API 为一等接口）、协议模板全集（legos）。

## 已知行为差异（有意保留，均有文档）

- `num_mutations` 对禁用字段计 0（上游可能仍计数）——UPSTREAM.md
- 条件隐藏块发射空载荷用例后已对齐上游；ordinal 无空洞
- UDP 载荷超限拒绝而非截断（5c 若做 server 模式可一并复核）
- RandomData 的计数怪癖（fuzz_values 计入随机条数）未复现——PRIMITIVES.md
- Float `num_mutations` 等于实际产出数（上游虚报 max_mutations）
- 上游 Repeat(variable=) docstring 声称禁用 fuzzing 但实现未禁用，本移植
  保留实现行为——VARIABLES.md
