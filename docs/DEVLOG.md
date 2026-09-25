# 开发历程（DEVLOG）

本文面向"可解释性评估"撰写：记录 moon-boofuzz 从立项到当前版本的开发过程、
关键技术决策、AI 工具的使用方式，以及踩过的坑。事实性内容以仓库提交历史
（56 个提交，全部位于 9 月赛期）与本仓库文档为依据，不虚构细节。

## 一、项目缘起

boofuzz 是 Python 生态里最成熟的协议模糊测试框架，但它的使用方式绑定
Python 运行时：把 boofuzz 嵌入其他语言的技术栈并不容易，执行结果的可复现性
也受 Python 环境影响。moon-boofuzz 的目标是把 boofuzz 的核心——协议数据模型、
确定性单字段变异、会话前置路径、结果记录与重放——移植为 MoonBit 库，
同时获得三个上游没有的性质：

1. **双目标**：核心编译到 Wasm 与 Native，网络/文件 I/O 走 Native；
2. **确定性**：同一输入的变异序列、随机数据流（MT19937）完全可复现；
3. **可验证的兼容性**：用上游真实运行产物做差分测试，而不是"看起来像"。

移植锚定上游固定 commit `518c13904fc32e7f2cc88c9dec934e509062953e`，
许可证沿用上游的 GPL-2.0-only，移植来源与兼容边界完整记录在
[UPSTREAM.md](UPSTREAM.md)。

## 二、开发时间线

开发按"先内核、再执行链、后外围"的顺序推进，与提交历史一致：

### 阶段 1：数据模型与原语
从 `Initialize MoonBit protocol mutation skeleton` 开始，第一批提交移植
simple/group 字段、整数编码与变异、二进制字节变异、字符串与分隔符变异。
这一阶段同时确立了包组织方式（每目录一个包、块风格 `///|`）和测试风格
（每个原语带参考向量与变异序列测试）。

### 阶段 2：块系统
依次移植嵌套命名块、条件块渲染、repeat 块、aligned 填充、动态 size 字段、
crc32 校验和字段。块系统是 boofuzz 数据模型的核心难点：长度字段的自动回填、
校验和字段"自身清零参与计算"的语义、条件块的渲染隐藏逻辑，全部有对应测试。

### 阶段 3：执行链闭环
会话图（前置请求路径）、Native TCP/UDP 传输、case 隔离执行器、case 生命周期
回调、JSONL 记录与重放、第一版 CLI（generate/run/replay/report）。到这里
项目第一次可以端到端跑通：定义协议 → 生成变异 → 发包 → 记录 → 重放。

### 阶段 4：上游对齐与健壮性
"upstream parity"批次补齐变异核心的组合枚举与会话变量；executor 分两批加入
errno 分类、会话开关、拨号重试/恢复、崩溃阈值（全局与元素级）、断点续跑、
节奏控制；edge callback 支持 challenge-response（读取响应写入会话变量，
供后续请求的动态字段消费）。

### 阶段 5：能力扩展
校验和算法集（adler32/crc32c/md5/sha1 + IPv4/UDP 校验和）、进程监视器、
IPv6 双栈、文件传输通道、CSV 导出、SQLite 结果层（`--db` 双写 +
`--record-passes` 节流窗口）、Web UI 与 `open` 子命令、UDP server/broadcast。

### 阶段 6：CI 稳定化
首次双平台 CI 暴露的问题逐个修复：llvm-mingw 下载 URL、ASan 锚点的格式稳定、
WinSock 进程级生命周期（并行测试下的访问冲突）、MSVC 下的崩溃报告器与
`stdib.h` 截断问题、`.CRT` 段符号定义。最终 Windows（MSVC 编译 C 桥）+
Linux（GCC，含 ASan）双平台绿灯，并完成了与上游语义对齐的复审修复批次。

### 阶段 7：HTTP 报文转换器（本批次）
`httpgen` 包把抓包得到的原始 HTTP 报文解析成可 fuzz 的协议定义：
请求行/头/体切分（含裸 LF 行结束）、按线序列出全部可 fuzz 段、冻结转换
字节级还原原文、每段可选文本/整数/bytes/random 变异原语。配套 `convert`
Web 页面（粘贴报文 → 预览 → 生成定义 JSON）、`cmd/httpfuzz` 示例
（离线打印变异、对真实 HTTP 服务执行 fuzz），以及从零走一遍库用法的
[CODE.md](CODE.md)。

### 阶段 8：工具链升级与告警清零
moonc v0.10.14（moon 0.1.20260920）把两个警告转为默认开启：
`implicit_impl_as_method`（trait impl 方法不再隐式提升）与
`test_unqualified_package`（黑盒测试隐式导入）。本次迁移通过一个 `.mbtx`
codemod（读取 `moon check --output-json` 自动定位修改点）分两轮完成：wasm
目标 50 个警告（40 条显式 `extend` + 13 处限定导入），native 目标 20 个
（native-only 的 transport/runner/process/db/recordio/web 包不在 wasm 检查图内，
首轮被遗漏）；`SessionView` 这类仅以 trait 限定形式调用的方法按编译器建议加
`#deprecated` 标记。清理后双目标 `--deny-warn` 均 0 警告，接口文件重新生成。
期间发现编译器 E0025 建议文本中的 `@moon-boofuzz.`（连字符）不是合法别名，
按声明的 `@moon_boofuzz` 修正。

## 三、关键技术决策

1. **用上游运行产物做差分，而非人工翻译期望值。** `fixtures/*.json` 由
   `scripts/fixtures.mbtx` 从上游 boofuzz（固定 commit）真实运行生成，每条
   记录同时携带 MoonBit 构造表达式与上游 Python 结果；`fixtures/db/oracle-run.db`
   是上游真实运行的 SQLite 产物，`db/oracle_fixture_test.mbt` 验证本项目能读
   上游写的库。移植正确性由此变成可执行断言。
2. **把 CPython 行为也钉死。** 上游是 Python 写的，浮点格式化、随机数流
   （MT19937 的 randint/getrandbits/uniform）必须与 CPython 逐一对拍，
   否则变异序列无法与上游一致。`float_test.mbt`、`mt19937_wbtest.mbt`
   承担这部分。
3. **自动化脚本一律用 `.mbtx`。** fixture 生成、全目标验证（verify）、
   ASan 批跑、oracle 差分、CI 日志解析都是 MoonBit 脚本模式，不引入
   shell/Python 粘合层，这与项目"用 MoonBit 写一切"的定位自洽。
4. **白盒测试只测私有内部行为。** runner 的拨号重试/阈值计数、mutation 流的
   内部状态用 `*_wbtest.mbt` 注入 mock；公开行为一律黑盒测试。
5. **诚实声明边界。** README 明确列出"仍不包含"清单（pedrpc 远程监视器、
   TLS、串口、Raw L2/L3、覆盖率引导等），不宣称完整兼容上游。

## 四、AI 工具的使用方式

本项目在开发过程中使用了 AI 编程代理，使用模式如下（对应章程的
可解释性要求）：

- **代理负责**：在人工审查与测试约束下编写/重构 MoonBit 源码与测试；
  编写 `.mbtx` 自动化脚本（fixture 生成、verify、asan、codemod）；分析上游
  源码并整理移植计划（`docs/PLAN.md` 按阶段勾销）；撰写仓库内技术文档；
  CI 失败的日志定位。
- **人工负责**：项目目标与兼容范围决策、每个批次的方向取舍、上游许可与
  发布合规核查、申报书（按 9 月章程要求本人撰写）、本文件"心得"一节的
  定稿、`moon publish` 发布决策（见 [ACCEPTANCE.md](ACCEPTANCE.md) 的
  发布清单——发布动作保留给维护者）。
- **约束机制**：所有 AI 参与的改动必须通过 `scripts/verify.mbtx`（fmt/info/
  双目标 check/build/test，全部 `--deny-warn`）与差分测试；`AGENTS.md`
  约定块风格与验证步骤，保证代理产出与仓库惯例一致。

## 五、踩过的坑

- **并行测试 + WinSock**：Windows CI 上多个测试并行初始化/清理 WinSock
  导致访问冲突，最终把 WSAStartup/WSACleanup 提为进程级生命周期解决
  （`109ef76`）。
- **MSVC 差异**：`malloc` 返回值被 int 截断、`.CRT` 段的崩溃报告器符号
  需要显式定义（`f3ed30a`、`ed93693`）。
- **浮点一致性**：`%f` 的默认精度、按精确二进制值舍入（而非缩放后的
  double）、宽指数进位，都按 CPython 实现细节钉死并写了针对性用例
  （`209a38b`）。
- **编译器建议未必可直接采纳**：E0025 的修复建议包含非法别名形式，
  照抄会引入 13 个编译错误，需要回到 `moon.pkg` 声明的别名。

## 六、数据小结（当前版本）

- MoonBit 源码约 2.4 万行（含测试），11 个包；
- 测试：50 个测试文件、211 个用例块（wasm 目标 128 个测试用例，全部通过，
  `--deny-warn` 下 0 警告 0 错误）；
- 双平台 CI（Windows MSVC + Linux GCC/ASan）；
- `docs/` 下 30 余篇按包/主题拆分的中文文档，另有发布前清单
  [ACCEPTANCE.md](ACCEPTANCE.md) 与移植边界说明 [UPSTREAM.md](UPSTREAM.md)。

## 七、心得

> 本节按 9 月章程"申报书务必人工撰写"的同样原则，由维护者本人补充定稿。
> 建议围绕以下要点展开（每点两三句即可）：
>
> 1. 立项时的真实痛点：为什么需要一个非 Python 运行时的 boofuzz；
> 2. 移植过程中印象最深的一次取舍（例如放弃 pedrpc 改为进程内监视器，
>    或 fixture 差分方案确立前的纠结）；
> 3. MoonBit 语言与工具链的切身体感（块组织、类型化错误、`.mbtx` 脚本模式、
>    双目标编译）；
> 4. 与 AI 协作的得与失：哪些环节代理显著提速，哪些判断必须自己拿。
