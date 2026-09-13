# 架构与功能提交清单

初始化保留 Static、Choice 和平面 Request。之后按计划的功能提交构建以下核心子集；每项同时包含实现、测试和来源/使用说明。第 21–30 项补齐上游变异核心。

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
|21|Size 自动边界变异|size.mbt，oracle 差分（140 边界）|
|22|Checksum 自动边界变异|checksum.mbt，oracle 差分（6 边界）|
|23|条件运算符补齐与隐藏用例发射|condition.mbt，condition_test.mbt|
|24|fuzz_values 通用机制|field.mbt，各构造器|
|25|Group+Block 笛卡尔|mutation.mbt CaseSeq 流，oracle 差分|
|26|RandomData|random_data.mbt，mt19937 差分|
|27|Float|float.mbt，oracle 差分（文本+IEEE754）|
|28|FromFile 等价|from_file.mbt|
|29|Mirror|mirror.mbt，primitives_fixture_test.mbt|
|30|MT19937 + 多点替换基础|mt19937.mbt，mt19937_wbtest.mbt|
|31|组合爆破 depth 1..N|mutation.mbt 组合流，oracle 差分|
|32|会话变量与动态字段/动态重复|model.mbt Dynamic 节点，session_variables_test.mbt|

纯核心、定义和记录格式不依赖网络。Native transport/recordio 只用 C 桥接系统调用；协议策略、变异、执行、分类与重放由 MoonBit 实现。执行顺序固定，每例创建新连接，不自动重试。

动态会话变量、边回调、组合爆破、覆盖率引导、并行执行和调试器留待后续版本。
