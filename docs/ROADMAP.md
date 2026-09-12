# 架构与功能提交清单

初始化保留 Static、Choice 和平面 Request。之后按计划的 20 个功能提交构建以下核心子集；每项同时包含实现、测试和来源/使用说明。

| # | 功能 | 主要实现/验证 |
|---|---|---|
|1|Simple / Group|field.mbt，simple_group_fixture_test.mbt|
|2|整数编码与边界|integer.mbt，integer_fixture_test.mbt|
|3|Bytes 变异|binary.mbt，binary_fixture_test.mbt|
|4|String / Delim|text.mbt，text_fixture_test.mbt|
|5|命名嵌套块|model.mbt，model_test.mbt|
|6|惰性用例流|mutation.mbt，mutation_wbtest.mbt|
|7|条件块|condition.mbt，condition_test.mbt|
|8|重复块|repeat.mbt，repeat_test.mbt|
|9|对齐|aligned.mbt，aligned_fixture_test.mbt|
|10|长度字段|size.mbt，size_fixture_test.mbt|
|11|CRC32|checksum.mbt，checksum_fixture_test.mbt|
|12|会话路径|session.mbt，session_test.mbt|
|13|Native TCP|transport/，回环测试和双平台 CI|
|14|Native UDP|transport/udp_wbtest.mbt|
|15|隔离执行器|runner/，真实 TCP/UDP 与注入测试|
|16|回调与分类|runner/monitor_wbtest.mbt|
|17|JSONL 记录|records/、recordio/，文件及 ASan 测试|
|18|保存序列重放|runner/replay_wbtest.mbt|
|19|JSON 定义和 generate/run|definition/、cmd/boofuzz/|
|20|replay/report 和完整场景|records/report.mbt、cmd/boofuzz/scenarios_wbtest.mbt|

纯核心、定义和记录格式不依赖网络。Native transport/recordio 只用 C 桥接系统调用；协议策略、变异、执行、分类与重放由 MoonBit 实现。执行顺序固定，每例创建新连接，不自动重试。

多字段笛卡尔积、动态会话变量、随机/浮点/文件原语、协议模板全集、覆盖率引导、并行执行和调试器留待后续版本。
