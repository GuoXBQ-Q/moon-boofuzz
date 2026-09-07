# moon-boofuzz

将 [boofuzz](https://github.com/jtpereyda/boofuzz) 的协议建模与变异测试核心移植到 MoonBit，为协议实现、解析器和服务端提供可复用的健壮性测试工具。

**状态：早期骨架，尚未完成 boofuzz 移植，尚未发布到 mooncakes.io。** 当前 API 不保证与上游兼容。项目用于 2026 年 9 月赛事「新生态项目建设」方向。

## 当前可以运行什么

- `Static`：固定字节字段。
- `Choice`：默认字节值和调用者给定的变异值。
- `Request`：平面字段序列，默认请求渲染、单字段逐次变异。
- 创建请求时复制字段数组和候选数组，避免调用者后续修改影响结果。
- 纯离线示例、黑盒测试和文档测试。

当前变异结果一次性保存在内存中，适用于小规模显式用例集；不包含自动边界值生成、网络发送、故障检测或重放。

## 本地开始

安装 [MoonBit](https://www.moonbitlang.com/download)。初始开发工具链：moonc v0.10.11，moon 0.1.20260827。

```sh
git clone https://github.com/GuoXBQ-Q/moon-boofuzz.git
cd moon-boofuzz
moon version --all
moon check --deny-warn
moon build
moon test --deny-warn
moon run cmd/main
```

GitHub 链接是预定发布地址，需由维护者首次推送后才能克隆。示例仅生成 `PING` 请求的两个变异用例，不连接网络。可运行 API 示例见 [README.mbt.md](README.mbt.md)。

## 预期使用场景

1. **二进制解析器回归测试**：开发者定义字段和边界值，离线生成输入，交给自己的解析器；保存触发错误的输入，作为修复后的固定回归用例。
2. **本地 TCP 服务健壮性测试**：开发者启动测试服务，以协议请求模板生成异常字段，执行并分类记录超时、断连和正常响应，再重放失败用例验证修复。
3. **有状态协议流程测试**：为自有协议描述握手、认证、业务请求的前置顺序，保留有效前置请求，仅变异目标步骤；每个用例重新建立状态，避免前一个失败污染后续测试。

以上为预期场景，当前骨架只实现其中的数据生成起点。

## 交付计划

计划实现整数/字节变异、嵌套 Block、长度及校验和字段、确定性用例编号、基础会话路径、TCP 连接、异常分类、结果持久化与重放。详见 [架构和阶段计划](docs/ROADMAP.md)。首版不承诺 boofuzz 全量 API 兼容、覆盖率引导、Web UI、串口、原始链路层或跨平台调试器。

## 项目结构

```text
moon.mod                模块元数据
moon.pkg                核心包与黑盒测试配置
primitive.mbt           字段模型
request.mbt             请求渲染与显式变异
request_test.mbt        行为测试
README.mbt.md           可执行 API 示例
cmd/main/               离线运行示例
.github/workflows/ci.yml 检查、构建、测试
docs/                   移植计划、来源说明、报名自查
```

## 来源与许可

采用 **GPL-2.0-only**，全文见 [LICENSE](LICENSE)。上游为 jtpereyda/boofuzz，研究基线为 `518c13904fc32e7f2cc88c9dec934e509062953e`。当前 MoonBit 源码为 AI 辅助编写的初始实现，参考上游概念，没有复制上游完整变异库；测试数据由本项目构造。后续移植将逐项记录来源与兼容边界，见 [UPSTREAM.md](docs/UPSTREAM.md)。本项目不是上游官方版本。

报名材料要求及尚需完成的事项见 [报名自查](docs/REGISTRATION.md)。
