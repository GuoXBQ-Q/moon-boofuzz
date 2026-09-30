# Web UI 与 open 子命令

`web/` 原生包提供 boofuzz 兼容的 Web 界面,对齐上游
`web/app.py` + `sessions/web_app.py` + `sessions/session_info.py`
(基线 `518c13904fc32e7f2cc88c9dec934e509062953e`,GPL-2.0-only)。

## HTTP 服务层

`web/http.c` 是最小 HTTP/1.1 回环服务桥,遵循 transport/socket.c 模板
(不透明句柄 + 错误槽、每对象 WSAStartup、非阻塞 fd、0/-1/-2 约定,
其中 -2 = "暂无连接/数据")。独立翻译单元无法共享 socket.c 的不透明
结构,故自带 listen/accept/wait/recv/send/close;仅绑定 127.0.0.1,
与上游默认 `localhost` 一致。

`HttpServer::bind(port)` 复刻上游 build_webapp_thread 的端口占用
重试(sessions/session.py:908-916):EADDRINUSE 时 port+=1 重新绑定,
最多 100 次;`port()` 返回实际绑定端口。请求读取到 `\r\n\r\n` 或
8KB 上限,只解析请求行;响应带 Content-Length 与 `Connection: close`。

`serve_pending(handler)` 非阻塞地服务当前积压的连接后返回,供
`run` 在用例之间调用;`WebUi::gate` 在每个用例前服务积压请求,若处于
暂停态则保持服务并休眠 50ms 循环——即上游 is_paused 与用例循环的联动
(暂停时 UI 的 /togglepause 仍可被服务,恢复后继续执行)。

## 路由(对齐 web/app.py)

| 路由 | 行为 |
| --- | --- |
| `/` | 进度条 + 暂停/恢复表单 + 崩溃列表(链接到 /test-case/<id>),内联 JS 每 2s 轮询 /api/current-run |
| `/togglepause` | 翻转会话暂停标志,302 回 `/` |
| `/test-case/<index>` | 服务端渲染的用例日志页(css_class 分色) |
| `/api/current-run` | `{"session_info": {...}}`:is_paused、current_index、num_mutations(未知为 null)、crashes、runtime、exec_speed 等 |
| `/api/test-case/<index>` | `{"index", "log_data":[{css_class, log_line}...]}`;未知索引 log_data 为 null |
| `/api/current-test-case` | 同上,index 取当前值 |

日志行渲染移植 helpers.py 的 test_step_info html 模板与 format_log_msg:
`Test Case:`/` Test Step:`/`Transmitted N bytes:`/`Received:`/
`Check Failed:`/`Check OK:`/`Error!!!!`,载荷按 `hex + python-repr`
展示,截断行带 "(data truncated for database storage)",css 类为
log-case/log-step/log-send/log-receive/log-fail/log-pass/log-error。

## 会话视图

`SessionView` 抽象上游 app.session 的两用形态:

- `LiveSession`(`run --web-port N`):计数与暂停标志在 Ref 中,
  capture 循环每例经 `observe` 推进 current_index/当前请求名/失败表;
  num_mutations 是**进度分母**:由定义编译后的各变异字段原语计数
  求和(上游 Session.num_mutations 同款语义),与 case 上限无关——
  组合爆破执行超过该分母时进度条钉满并变为琥珀色,百分比标签改显
  "+N beyond plan"(计划外已执行的用例数),零变异定义显示 Unbounded。
  **用例详情页在运行期间可用**:observe 同时保留每条记录,
  `/test-case/<index>` 按已执行用例即时渲染收发字节(等价上游从
  live-written db 取详情);尚未执行到的索引渲染"未执行"提示,
  内存占用随已执行用例数增长。
- `OfflineSession`(`open FILE`):等价 session_info.SessionInfo 的
  只读视图——is_paused 恒 false、state "finished"、runtime/exec_speed
  0、current_index 为持久化用例数(上游 COUNT(*))。支持两种后端:
  SQLite 结果库(经 DbReader)与 JSONL 记录文件(内存索引,
  按记录序数/结果构造与 DB 行一致的视图,失败表排除 error 型连接失败)。

页面为手写的 HTML/CSS/JS 最小子集(内联,无静态文件服务)。

## CLI

- `run [--web-port N]`:实时 UI 与上游一致**默认开启**,端口 26000
  (上游 DEFAULT_WEB_UI_PORT),端口被占时自动顺延重试;打印
  "Web interface can be found at http://localhost:PORT"。
  `--web-port 0` 请求操作系统分配随机空闲端口。与上游的两点差异:
  CLI 无关闭开关(上游亦无,仅程序化 web_port=None 可关),以及跑完
  输出摘要后直接退出——不复刻上游 `--keep-web` 阻塞等待回车的交互,
  批处理与 CI 才能正常收尾;需要事后翻看时用 `open` 重开只读视图。
- `open FILE [--ui-port N]`:离线打开 SQLite 结果库或 JSONL 记录,
  默认端口 26000,打印上游同款 "Serving web page at ..." 后常驻服务,
  Ctrl+C 退出。文件类型按 16 字节 SQLite 魔数判别。

## 测试

`web/web_wbtest.mbt`:真实回环 socket 请求各路由,断言 JSON 形状
(session_info 字段、crashes、log_data 的 css/log_line)、
/togglepause 的 302 与标志翻转、index/test-case 页渲染、404 与端口
+1;OfflineSession 的 JSONL 与 SQLite 双后端、LiveSession 的 observe
与 gate;`cmd/boofuzz/cli_wbtest.mbt` 覆盖 `run --web-port` 端到端。

边界:仅回环、单线程顺序服务(UI 请求在用例间隙被服务,长阻塞用例
期间会延迟);单个坏连接(静默客户端读超时、畸形请求行、连上即关)
被静默丢弃、路由处理器异常回 500,都不会中断服务或活动运行(对齐
上游每请求独立 worker 线程的隔离性);无 HTTPS、无静态文件、无
Flask 模板全集;启动失败的 procmon synopsis 不入库,目标崩溃的退出
码随用例的 `monitor_failed` outcome 与 detail 记录;test-case 详情页对未知或未持久化的用例渲染
提示页(200)而非 404,活动运行的崩溃链接保持可点击,对齐上游空页面
行为。其余已知差异:端口占用自动 +1 最多尝试 100 次(上游不限);
离线视图的 /togglepause 静默无效果(上游会 500);live 运行时长/速度
统计包含暂停时间(上游扣除);index 页无按元素进度条与千位分组。

Source: `boofuzz/web/app.py`(路由 :26-91、_get_log_data :54-65)、
`boofuzz/sessions/session.py` build_webapp_thread(:904-920)、
`boofuzz/sessions/session_info.py`、`boofuzz/sessions/web_app.py`、
`boofuzz/helpers.py` test_step_info(:29-102)与 format_log_msg
(:359-399)、`boofuzz/data_test_case.py`、`boofuzz/data_test_step.py`。
`web/http.c`、`SessionView`/`LiveSession`/`OfflineSession`、页面渲染
为 MoonBit 适配。

## 深色控制台界面

概览、用例日志与 HTTP 转换器共享石墨灰界面和响应式布局。概览显示执行计数、故障记录、配置进度和连接状态；轮询同步进度条与故障列表，未知上限不显示虚构的百分比。离线结果明确标为 Saved run / Read-only，隐藏暂停和实时计时控件。

故障列表可在当前页面按索引或原因筛选；Case inspector 按索引打开日志。用例页支持 All events / Traffic / Checks / Failures 筛选与复制可见日志，未知用例提供明确的空状态。所有记录内容保留 HTML 转义，实时更新通过 textContent 构造。

HTTP 转换器使用 Request / Mutations / Definition 三步布局，提供示例填充、全部选择/清除、选择计数、参数按策略显示、JSON 复制反馈与下载。界面不依赖外部字体、脚本或静态文件服务。

/api/current-run 的 session_info 新增 state，保留原有字段。LiveSession 的 current_index 为本次已完成用例数；故障链接仍使用记录中的原始 ordinal。open 使用有界文件头读取识别 SQLite/JSONL，避免把 16 字节前缀检测误作整文件大小上限。
