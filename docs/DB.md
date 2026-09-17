# SQLite 结果库

`db/` 原生包提供 boofuzz 兼容的 SQLite 结果持久化,对齐上游
`fuzz_logger_db.py` 的 `FuzzLoggerDb` / `FuzzLoggerDbReader`
(基线 `518c13904fc32e7f2cc88c9dec934e509062953e`,GPL-2.0-only)。

## 内嵌 SQLite

`db/sqlite3.c` / `db/sqlite3.h` 是 SQLite 3.45.3 amalgamation 的**未修改**
副本(版本与上游 CI 产物库的写入版本一致)。SQLite 公有领域,与项目
GPL-2.0-only 兼容;来源 sqlite.org,版本记录于 amalgamation 文件头。

## C 桥

`db/sqlite.c` 遵循 transport/socket.c 与 process/process.c 模板:不透明
句柄 + int 错误槽,GC finalizer 释放资源(`sqlite3_close_v2` /
`sqlite3_finalize`,容忍未 finalize 的语句),返回约定 0 = 成功、
-1 = 失败(SQLite 结果码在错误槽)、-2 = "有行可读"(`bf_stmt_step`,
对应 process.c 的 still-running)。路径与 SQL 均按长度收 UTF-8 字节,
C 层复制成 NUL 结尾缓冲,不依赖 MoonBit Bytes 的结尾约定。

MoonBit 侧:`Db::open/exec/prepare/close`、`Stmt::run/query/close`、
`DbValue`(Null/Int/Float/Text/Blob)与 `DbRow`。`run`/`query` 每次先
reset 再绑定(对齐 python cursor.execute 的隐式重置),语句错误以
`DbError` 抛出,携带 SQLite 结果码。

## 写入端:FuzzLoggerDb 等价

`DbLogger::open(path, num_log_cases~)` 建库:仅当 `cases` 表不存在时执行
上游 DDL(fuzz_logger_db.py:40-50):

- `cases(name text, number integer, timestamp TEXT)`
- `steps(test_case_index integer, type text, description text, data blob, timestamp TEXT, is_truncated BOOLEAN)`

日志方法与上游一一对应:`open_test_case`(入队 + 采纳 index)、
`open_step`/`log_check`/`log_info`/`log_send`/`log_recv`/`log_pass`、
`log_fail`(置失败标记)、`log_error`(置失败标记并**立即**刷写,
fuzz_logger_db.py:119-132)、`close_test_case`(尝试刷写)、
`close_test`(强制刷写)。

`_write_log` 语义逐条保留(fuzz_logger_db.py:206-225):

- `num_log_cases > 0` 时先按 `当前 index − 队首 index >= N` 弹出,只保留
  最近 N 个用例;`num_log_cases = 0` 时强制刷写(全量)。
- 仅在 强制 / 失败 / 首个用例 时写库;批内 `BEGIN`…`COMMIT`(等价
  python 的隐式事务 + commit)。
- 首个用例必定落库(上游 `_log_first_case`)。
- 非失败批次做 512 字节截断(`_truncate_send_recv`,
  fuzz_logger_db.py:227-230):超限则 `data` 截到 512、`is_truncated`
  置真;**失败用例保留完整载荷**。上游以 `"recv"` 匹配类型而日志行
  实为 `"receive"`,因此实际上只有 `send` 行会被截断;本移植逐字
  保留该 quirk,两侧结果库保持字节可比。阈值常量
  `DATA_TRUNCATE_LENGTH`。

时间戳为 UTC ISO-8601(微秒精度,微秒为 0 时省略小数部分),与上游
`helpers.get_time_stamp()` 的 `datetime.now(utc).replace(tzinfo=None)
.isoformat()` 一致;测试可经 `open_with_clock` 注入固定时钟。

`DbLogger::log_record(record)` 把 JSONL 的 `CaseRecord` 重放为上游日志
序列:`cases` 行(`name`=request_name、`number`=ordinal)→ 每步一行
`step`(description=消息名)+ `send`/`receive` 行 → 结果行
(`pass`,失败时 `fail`;连接失败(`failed_step = -1`)按上游走
`log_error`)→ 用例关闭。

## 读取端:FuzzLoggerDbReader 等价

`DbReader::open(path)` 打开现有库(本包或上游写入的均可):

- `get_test_case_data(index)`:cases 行 + 按插入序的 steps 行;缺失抛
  `NoSuchCase`(等价 `BoofuzzNoSuchTestCase`)。
- `query(sql, params?)`:原始 SQL + 位置参数,返回全部 `DbRow`(收集式
  游标等价)。
- `failure_map()`:`type='fail'` 的步骤按 `test_case_index` 聚合
  description(`error` 行不入表,对齐上游)。

## CLI

- `run --db FILE`:JSONL 与 SQLite 双写;`run_summary` 增加 `database`。
- `run --record-passes N`:keep-only-n 节流,两侧共用(N=0 全量)。JSONL
  侧由 `recordio/ThrottledWriter` 实现(记录级环形缓冲,首例 + 失败立即
  刷 + 收尾回填最近 N 例),SQLite 侧即 `num_log_cases`。

## 测试与差分

- `db/db_test.mbt`:open/exec/prepare 往返、全量记录、failure_map 与
  NoSuchCase、keep-only-n 首例+窗口、512 截断(通过例截断/失败例完整)、
  重开续写。
- `db/oracle_fixture_test.mbt`:`fixtures/db/oracle-run.db` 是上游 boofuzz
  0.4.2 真实 CI 运行产物(SQLite 3.45.3 写入的空库),验证本层可读上游
  schema;并以上游逐字 SQL(含 `;\n` 后缀)写入后读回。
- `recordio/throttle_wbtest.mbt`、`cmd/boofuzz/cli_wbtest.mbt`:节流语义
  与 `--db`/`--record-passes` 端到端。
- ASan:`scripts/asan.mbtx` 已纳入 `db/`。

边界:单线程使用(无 busy 重试/WAL);不移植 pedrpc、curses 等上游外围;
数据列只收 Integer/Float/Text/Blob,库内无浮点 schema 列。其余已知差异:
schema 重建以 `cases` 表存在为准(上游以文件不存在为准,已存在的
异构库上游会写失败而本移植会补建表);写失败时缓冲区中最后 N 条通过
用例随事务丢失(与上游崩溃时的未提交事务一致);写侧无上游
`FuzzLoggerDb.get_test_case_data` 读取接口,读取统一走 `DbReader`。

Source: `boofuzz/fuzz_logger_db.py`(表结构 :46-50、`_write_log`
:206-225、截断 :227-230、Reader :233-289)、
`boofuzz/data_test_case.py`、`boofuzz/data_test_step.py`。
`db/sqlite.c`、`recordio/throttle.mbt`、`DbLogger::log_record` 映射为
MoonBit 适配。测试覆盖见上。
